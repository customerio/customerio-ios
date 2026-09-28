@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import SharedTests
import Testing

@Suite("Replay harness", .serialized, .enabled(if: ReplayRuntime.isMonitorAvailable))
@MainActor
struct ReplayHarnessTests {
    private static let latitude = 10.00000
    private static let longitude = 20.00000
    /// Outside the fence, so the baseline is `exit` and the first `enter` is a real change.
    private static let awayLatitude = 10.01510
    /// Past `contradictionGateReplayWindow`: inside it an enter while still outside is refused.
    private static let arrivalAt: TimeInterval = 30

    private func catalogue(_ fenceId: String) -> String {
        """
        [{"id":"\(fenceId)","name":"F","latitude":\(Self.latitude),"longitude":\(Self.longitude),"radius":250,"transitionTypes":["enter","exit"],"geosetIds":["7"]}]
        """
    }

    @available(iOS 17.0, *)
    private func registered(_ harness: ReplayHarness, fenceId: String) async throws {
        try harness.enqueueFetch(bodyJSON: catalogue(fenceId))
        harness.loadPulledFixes(stimuli: [0, Self.arrivalAt], samples: [
            harness.pulledFix(
                latitude: Self.awayLatitude,
                longitude: Self.longitude,
                accuracy: 10,
                age: 0,
                at: 0
            ),
            harness.pulledFix(
                latitude: Self.latitude,
                longitude: Self.longitude,
                accuracy: 10,
                age: 0,
                at: Self.arrivalAt
            )
        ])
        harness.setIdentified(true)
        // `onIdentified` arms on a Task; a bus fix fed before it lands starts no sync.
        #expect(
            await settleOnMain { harness.acquireFixCallCount >= 1 },
            "identify did not arm for a fix"
        )
        harness.feedFix(
            latitude: Self.awayLatitude,
            longitude: Self.longitude,
            accuracy: nil,
            age: 0,
            source: .bus
        )
        try await harness.settleBoundaries()
        #expect(
            await settleOnMain { harness.emitted(ev: "registration.applied").count == 1 },
            "setup did not reach a registered state: \(harness.emitted.map { $0["ev"] ?? "?" })"
        )
        // From here the cache answers inside the fence, so an `enter` agrees with it.
        await harness.advance(to: Self.arrivalAt)
        harness.resetOutput()
    }

    /// The bus fix at the end is the control, so a harness delivering no fix at all cannot pass.
    @Test
    @available(iOS 17.0, *)
    func feedFix_givenResolverSourcedRead_expectInertUntilBusFixArrives() async throws {
        try await ReplayHarness.withTail {
            let harness = ReplayHarness()
            try harness.enqueueFetch(bodyJSON: catalogue("A"))
            harness.loadPulledFixes(stimuli: [0], samples: [
                harness.pulledFix(
                    latitude: Self.awayLatitude,
                    longitude: Self.longitude,
                    accuracy: 10,
                    age: 0,
                    at: 0
                )
            ])
            harness.setIdentified(true)
            #expect(
                await settleOnMain { harness.acquireFixCallCount >= 1 },
                "identify did not arm for a fix"
            )

            harness.feedFix(
                latitude: Self.awayLatitude,
                longitude: Self.longitude,
                accuracy: 10,
                age: 0,
                source: .resolver
            )
            try await harness.settleBoundaries()
            #expect(harness.fetchCount == 0, "a cache read started a sync")
            #expect(harness.emitted(ev: "registration.applied").isEmpty)

            harness.feedFix(
                latitude: Self.awayLatitude,
                longitude: Self.longitude,
                accuracy: nil,
                age: 0,
                source: .bus
            )
            try await harness.settleBoundaries()
            #expect(
                await settleOnMain { harness.emitted(ev: "registration.applied").count == 1 },
                "the bus fix did not drive the sync: \(harness.emitted.map { $0["ev"] ?? "?" })"
            )
        }
    }

    @Test
    @available(iOS 17.0, *)
    func deliverCrossing_givenArmedFence_expectTransitionAccepted() async throws {
        try await ReplayHarness.withTail {
            let harness = ReplayHarness()
            try await registered(harness, fenceId: "A")

            harness.deliverCrossing(fence: "A", transition: .enter)
            await Task.yield()
            await settleOnMain { harness.emitted(ev: "transition.accepted").count == 1 }

            let accepted = harness.emitted(ev: "transition.accepted")
            #expect(accepted.count == 1, "emitted: \(harness.emitted.map { $0["ev"] ?? "?" })")
            #expect(accepted.first?["id"] == "A")
            #expect(accepted.first?["t"] == "enter")
        }
    }

    /// Each `enter` follows an `exit`, or dedup discards it before the cooldown is consulted. Each
    /// crossing needs its own instant, or it reads as a re-delivery.
    @Test
    @available(iOS 17.0, *)
    func deliverCrossing_givenVirtualTimePastCooldown_expectTransitionAccepted() async throws {
        try await ReplayHarness.withTail {
            let harness = ReplayHarness()
            try await registered(harness, fenceId: "A")

            @MainActor func cross(_ transition: GeofenceTransition, at: TimeInterval) async throws {
                await harness.advance(to: at)
                let accepted = harness.emitted(ev: "transition.accepted").count
                harness.deliverCrossing(fence: "A", transition: transition)
                try await harness.settleBoundaries()
                await settleOnMain { harness.emitted(ev: "transition.accepted").count > accepted }
            }

            try await cross(.enter, at: Self.arrivalAt + 1)
            #expect(harness.emitted(ev: "transition.accepted").contains { $0["t"] == "enter" })
            try await cross(.exit, at: Self.arrivalAt + 2)

            // A wall-clock read would also suppress here; the next leg is what proves anything.
            harness.resetOutput()
            try await cross(.enter, at: 60)
            #expect(
                !harness.emitted(ev: "transition.accepted").contains { $0["t"] == "enter" },
                "a repeat inside the cooldown must not be accepted"
            )

            try await cross(.exit, at: GeofenceConstants.eventCooldownInterval + 120)
            harness.resetOutput()
            try await cross(.enter, at: GeofenceConstants.eventCooldownInterval + 121)
            #expect(
                harness.emitted(ev: "transition.accepted").contains { $0["t"] == "enter" },
                "virtual time moved past the cooldown but the SDK did not follow it — the clock gap DOES block replay"
            )
        }
    }

    /// Two deliveries at one virtual instant share a `date`, like a CoreLocation re-delivery.
    @Test
    @available(iOS 17.0, *)
    func deliverCrossing_givenSameEventTwice_expectSecondDropped() async throws {
        try await ReplayHarness.withTail {
            let harness = ReplayHarness()
            try await registered(harness, fenceId: "A")

            harness.deliverCrossing(fence: "A", transition: .enter)
            harness.deliverCrossing(fence: "A", transition: .enter)
            try await harness.settleBoundaries()
            await settleOnMain { harness.emitted(ev: "os.callback.dropped").count == 1 }

            #expect(harness.emitted(ev: "transition.accepted").count == 1)
            let dropped = harness.emitted(ev: "os.callback.dropped")
            #expect(dropped.count == 1)
            #expect(dropped.first?["why"] == GeofenceMonitorEventOutcome.suppressedRedelivery.diagnosticReason)
        }
    }

    @Test
    @available(iOS 17.0, *)
    func deliverCrossing_givenDistinctEvents_expectNeitherDropped() async throws {
        try await ReplayHarness.withTail {
            let harness = ReplayHarness()
            try await registered(harness, fenceId: "A")

            harness.deliverCrossing(fence: "A", transition: .enter)
            try await harness.settleBoundaries()
            await settleOnMain { harness.emitted(ev: "transition.accepted").count == 1 }
            await harness.advance(to: Self.arrivalAt + 120)
            harness.deliverCrossing(fence: "A", transition: .exit)
            try await harness.settleBoundaries()
            await settleOnMain { harness.emitted(ev: "transition.accepted").count == 2 }

            #expect(harness.emitted(ev: "os.callback.dropped").isEmpty)
            #expect(harness.emitted(ev: "transition.accepted").count == 2)
        }
    }

    /// New by state, but older by date than the last event processed.
    @Test
    @available(iOS 17.0, *)
    func deliverCrossing_givenCopyOfOlderEventAfterBaselineMoved_expectRefusedAsStale() async throws {
        try await ReplayHarness.withTail {
            let harness = ReplayHarness()
            try await registered(harness, fenceId: "A")

            harness.deliverCrossing(fence: "A", transition: .enter, identity: Self.arrivalAt)
            try await harness.settleBoundaries()
            await settleOnMain { harness.emitted(ev: "transition.accepted").count == 1 }
            await harness.advance(to: Self.arrivalAt + 60)
            harness.deliverCrossing(fence: "A", transition: .exit, identity: Self.arrivalAt + 60)
            try await harness.settleBoundaries()
            await settleOnMain { harness.emitted(ev: "transition.accepted").count == 2 }
            harness.deliverCrossing(fence: "A", transition: .enter, identity: Self.arrivalAt)
            try await harness.settleBoundaries()
            await settleOnMain { harness.emitted(ev: "os.callback.dropped").count == 1 }

            #expect(harness.emitted(ev: "transition.accepted").count == 2)
            let dropped = harness.emitted(ev: "os.callback.dropped")
            #expect(dropped.count == 1)
            #expect(dropped.first?["why"] == GeofenceMonitorEventOutcome.suppressedRedelivery.diagnosticReason)
        }
    }

    @Test
    @available(iOS 17.0, *)
    func deliverCrossing_givenAnyEmission_expectMachineTail() async throws {
        try await ReplayHarness.withTail {
            let harness = ReplayHarness()
            try await registered(harness, fenceId: "A")
            harness.deliverCrossing(fence: "A", transition: .enter)
            _ = await settleOnMain { !harness.emitted.isEmpty }

            #expect(!harness.emitted.isEmpty)
            #expect(harness.emitted.allSatisfy { $0["ev"] != nil })
        }
    }

    @Test
    @available(iOS 17.0, *)
    func wireMonitor_givenAlreadyAdopted_expectSecondRunRearmsNothing() async throws {
        try await ReplayHarness.withTail {
            let harness = ReplayHarness()
            try await registered(harness, fenceId: "A")

            // The double survives `reenterProcess()` and already holds setup's operations.
            let armedBeforeRelaunch = harness.conditionMonitor.operations.count

            harness.reenterProcess()
            await harness.wireMonitor()
            try await harness.settleBoundaries()
            _ = await settleOnMain { harness.emitted(ev: "registration.adopted").count == 1 }
            let armedOnce = harness.conditionMonitor.operations.count
            #expect(armedOnce > armedBeforeRelaunch, "the first adopt re-armed nothing")

            await harness.wireMonitor()
            try await harness.settleBoundaries()

            #expect(harness.emitted(ev: "registration.adopted").count == 1, "the second run adopted again")
            #expect(harness.conditionMonitor.operations.count == armedOnce, "the second run drove the OS: \(harness.conditionMonitor.operations[armedOnce...])")
        }
    }
}
