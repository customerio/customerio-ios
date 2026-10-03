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

    private func catalogue(_ fenceId: String, dwellThresholdSeconds: Int? = nil) -> String {
        let dwell = dwellThresholdSeconds.map { ",\"dwellThresholdSeconds\":\($0)" } ?? ""
        return """
        [{"id":"\(fenceId)","name":"F","latitude":\(Self.latitude),"longitude":\(Self.longitude),"radius":250,"transitionTypes":["enter","exit"],"geosetIds":["7"]\(dwell)}]
        """
    }

    /// `registrationFixAge` is how old the cached position the registration reads is; nil for none
    /// at all, which leaves the SDK assuming the device is outside rather than knowing it.
    @available(iOS 17.0, *)
    private func registered(
        _ harness: ReplayHarness,
        fenceId: String,
        dwellThresholdSeconds: Int? = nil,
        registrationFixAge: TimeInterval? = 0
    ) async throws {
        try harness.enqueueFetch(bodyJSON: catalogue(fenceId, dwellThresholdSeconds: dwellThresholdSeconds))
        harness.loadPulledFixes(stimuli: [0, Self.arrivalAt], samples: [
            registrationFixAge.map {
                harness.pulledFix(
                    latitude: Self.awayLatitude,
                    longitude: Self.longitude,
                    accuracy: 10,
                    age: $0,
                    at: 0
                )
            } ?? harness.emptyPull(at: 0),
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

    /// Replay composes dwell as production does. Left to the DI default, bootstrap resolved
    /// `GeofenceDwellCoordinator.shared` — built from whichever harness touched it first — and
    /// awaited it inside the process-global run chain, while this composition's resolver and
    /// coordinator ran the pre-dwell paths production no longer takes.
    @Test
    @available(iOS 17.0, *)
    func deliverCrossing_givenArmedDwellCircle_expectVisitRecordedByThisComposition() async throws {
        try await ReplayHarness.withTail {
            let harness = ReplayHarness()
            defer { harness.detachFromBootstrap() }
            #expect(harness.bootstrapResolvesOwnDwellCoordinator)
            try await registered(harness, fenceId: "A", dwellThresholdSeconds: 60)

            harness.deliverCrossing(fence: "A", transition: .enter)
            await Task.yield()
            await settleOnMain { harness.emitted(ev: "transition.accepted").count == 1 }

            #expect(harness.emitted(ev: "transition.accepted").first?["t"] == "enter")
            // Recorded after the ENTER is tracked, so it can trail the acceptance by a hop or two.
            var visit = await harness.storedVisit(fence: "A")
            for _ in 0 ..< 200 where visit == nil {
                try await Task.sleep(nanoseconds: 10000000)
                visit = await harness.storedVisit(fence: "A")
            }
            #expect(visit?.entryObserved == true)
        }
    }

    /// Registered with no fix, or one too old to settle the side, the condition is added ASSUMING
    /// the device is outside. `CLMonitor` answers a wrong assumption with the real state, so the
    /// ENTER that follows may describe a device that was inside all along: still delivered, but the
    /// visit it starts is a candidate whose start is not reported as an entry.
    @Test(arguments: [nil, 600] as [TimeInterval?])
    @available(iOS 17.0, *)
    func deliverCrossing_givenAssumedOutsideBaseline_expectEnterDeliveredAndVisitCandidate(
        registrationFixAge: TimeInterval?
    ) async throws {
        try await ReplayHarness.withTail {
            let harness = ReplayHarness()
            defer { harness.detachFromBootstrap() }
            try await registered(
                harness, fenceId: "A", dwellThresholdSeconds: 60, registrationFixAge: registrationFixAge
            )

            let visit = try await enterAndAwaitVisit(harness, fenceId: "A")

            #expect(harness.emitted(ev: "transition.accepted").first?["t"] == "enter")
            #expect(visit != nil, "the ENTER started no visit, so this test proves nothing")
            #expect(visit?.entryObserved == false, "an assumption's correction was dated as an entry")
        }
    }

    /// `.unmonitored` means the OS stopped watching the fence, so the stored entry can no longer
    /// vouch for a continuous stay. Kept, a later EXIT or dwell would measure across the gap.
    @Test
    @available(iOS 17.0, *)
    func deliverMonitorStopped_givenOpenDwellVisit_expectVisitInvalidated() async throws {
        try await ReplayHarness.withTail {
            let harness = ReplayHarness()
            defer { harness.detachFromBootstrap() }
            try await registered(harness, fenceId: "A", dwellThresholdSeconds: 60)
            try await enterAndAwaitVisit(harness, fenceId: "A")

            harness.deliverMonitorStopped(fence: "A")

            var visit = await harness.storedVisit(fence: "A")
            for _ in 0 ..< 200 where visit != nil {
                try await Task.sleep(nanoseconds: 10000000)
                visit = await harness.storedVisit(fence: "A")
            }
            #expect(visit == nil, "an unmonitored fence kept its visit")
        }
    }

    /// The movement trigger carries no visit; its loss must not end a business fence's stay.
    @Test
    @available(iOS 17.0, *)
    func deliverMonitorStopped_givenMovementTrigger_expectBusinessVisitKept() async throws {
        try await ReplayHarness.withTail {
            let harness = ReplayHarness()
            defer { harness.detachFromBootstrap() }
            try await registered(harness, fenceId: "A", dwellThresholdSeconds: 60)
            let visit = try await enterAndAwaitVisit(harness, fenceId: "A")

            harness.deliverMonitorStopped(fence: GeofenceConstants.movementTriggerIdentifier)
            #expect(
                await settleOnMain {
                    harness.emitted(ev: "os.monitor.stopped")
                        .contains { $0["id"] == GeofenceConstants.movementTriggerIdentifier }
                },
                "the trigger's stop was never processed, so this test proves nothing"
            )
            try await harness.settleBoundaries()
            for _ in 0 ..< 10 {
                await Task.yield()
            }

            #expect(await harness.storedVisit(fence: "A") == visit)
        }
    }

    @discardableResult
    @available(iOS 17.0, *)
    private func enterAndAwaitVisit(_ harness: ReplayHarness, fenceId: String) async throws -> GeofenceDwellVisit? {
        harness.deliverCrossing(fence: fenceId, transition: .enter)
        await Task.yield()
        await settleOnMain { harness.emitted(ev: "transition.accepted").count == 1 }
        var visit = await harness.storedVisit(fence: fenceId)
        for _ in 0 ..< 200 where visit == nil {
            try await Task.sleep(nanoseconds: 10000000)
            visit = await harness.storedVisit(fence: fenceId)
        }
        #expect(visit != nil, "the ENTER never recorded a visit")
        return visit
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
