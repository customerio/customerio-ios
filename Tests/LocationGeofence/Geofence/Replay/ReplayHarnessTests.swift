@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import SharedTests
import Testing

/// The harness's own tests: the SDK can be driven without a device or the OS, on a clock the test
/// controls. A scenario replay only means something if these hold.
@Suite("Replay harness", .serialized, .enabled(if: ReplayRuntime.isMonitorAvailable))
@MainActor
struct ReplayHarnessTests {
    /// The fence.
    private static let latitude = 10.00000
    private static let longitude = 20.00000
    /// Where the device sits while the fence is registered — well outside it, so the SDK's baseline
    /// is `exit` and the first delivered `enter` is a real change rather than a duplicate.
    private static let awayLatitude = 10.01510
    /// When the device reaches the fence.
    ///
    /// Past `contradictionGateReplayWindow` (10 s) on purpose. Inside it the SDK vets an OS event
    /// against a fresh fix (a CLMonitor re-add replays the daemon's stale belief), so an enter at
    /// registration time with the device still outside is rightly refused.
    private static let arrivalAt: TimeInterval = 30

    /// One fence, as the API would return it.
    private func catalogue(_ fenceId: String) -> String {
        """
        [{"id":"\(fenceId)","name":"F","latitude":\(Self.latitude),"longitude":\(Self.longitude),"radius":250,"transitionTypes":["enter","exit"],"geosetIds":["7"]}]
        """
    }

    /// Brings the SDK to a registered state the way a real app does: answer its fetch, give it a
    /// position, sign a user in. Nothing is written to the SDK's own state directly.
    @available(iOS 17.0, *)
    private func registered(_ harness: ReplayHarness, fenceId: String) async throws {
        try harness.enqueueFetch(bodyJSON: catalogue(fenceId))
        // A `manager_cache` position is pulled, so it is loaded as the cache's value, not delivered.
        harness.loadPulledFixes(stimuli: [0, Self.arrivalAt], samples: [
            harness.pulledFix(
                latitude: Self.awayLatitude,
                longitude: Self.longitude,
                accuracy: 10,
                age: 0,
                at: 0
            ),
            // Where the device is once it has driven in.
            harness.pulledFix(
                latitude: Self.latitude,
                longitude: Self.longitude,
                accuracy: 10,
                age: 0,
                at: Self.arrivalAt
            )
        ])
        harness.setIdentified(true)
        // `onIdentified` arms for the next fix on a Task (and calls `acquireFix` in `.automatic`).
        // A bus fix fed before that lands finds nothing armed and no sync starts.
        #expect(
            await settleOnMain { harness.acquireFixCallCount >= 1 },
            "identify did not arm for a fix"
        )
        // A fix arriving from the Location module drives the sync; the pull above only answers
        // reads made once it is running.
        harness.feedFix(
            latitude: Self.awayLatitude,
            longitude: Self.longitude,
            accuracy: nil,
            age: 0,
            source: .bus
        )
        // The fetch is a boundary, and a hand-written setup has no drive to answer it.
        try await harness.settleBoundaries()
        #expect(
            await settleOnMain { harness.emitted(ev: "registration.applied").count == 1 },
            "setup did not reach a registered state: \(harness.emitted.map { $0["ev"] ?? "?" })"
        )
        // The drive in: from here the cache answers with the fence's coordinates, so an arriving
        // `enter` agrees with the world.
        await harness.advance(to: Self.arrivalAt)
        harness.resetOutput()
    }

    /// A `prov=resolver` record is the SDK reading, not a position arriving; only the bus event
    /// reaches `GeofenceRefreshTrigger`. Delivered as an arrival it would consume identify's rearm
    /// flag and start a sync the drive never ran.
    ///
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

    /// The cooldown follows virtual time, not the wall clock. If it read the wall clock, every
    /// duration in a replayed scenario would be meaningless while still passing.
    ///
    /// Each `enter` is preceded by an `exit` so it is a genuine state change; otherwise the dedup
    /// baseline discards it and the cooldown is never consulted. Cooldown is keyed per
    /// `user:fence:transition`, so the exits do not consume the enter's window.
    ///
    /// Every crossing gets its own instant: two events for one condition sharing a date are one
    /// event re-delivered, and the second would be refused as such.
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
                // No recording here, so answer any fetch the crossing's follow-up parked.
                try await harness.settleBoundaries()
                await settleOnMain { harness.emitted(ev: "transition.accepted").count > accepted }
            }

            try await cross(.enter, at: Self.arrivalAt + 1)
            #expect(harness.emitted(ev: "transition.accepted").contains { $0["t"] == "enter" })
            try await cross(.exit, at: Self.arrivalAt + 2)

            // Inside the cooldown in virtual time. A wall-clock read would also suppress here; it is
            // the pair with the next leg that proves anything.
            harness.resetOutput()
            try await cross(.enter, at: 60)
            #expect(
                !harness.emitted(ev: "transition.accepted").contains { $0["t"] == "enter" },
                "a repeat inside the cooldown must not be accepted"
            )

            // Past the cooldown in virtual time, but still well under a second of real time. A
            // wall-clock read cannot produce an acceptance here; only the injected clock can.
            try await cross(.exit, at: GeofenceConstants.eventCooldownInterval + 120)
            harness.resetOutput()
            try await cross(.enter, at: GeofenceConstants.eventCooldownInterval + 121)
            #expect(
                harness.emitted(ev: "transition.accepted").contains { $0["t"] == "enter" },
                "virtual time moved past the cooldown but the SDK did not follow it — the clock gap DOES block replay"
            )
        }
    }

    /// CoreLocation hands the same event over more than once, sharing a `date`. Two deliveries at
    /// one virtual instant model that, and the copy is refused by date before its state is compared.
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

    /// A genuinely different event must not be swallowed; advancing the clock gives it its own date.
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

    /// A copy of an *earlier* event arriving after the baseline has moved on (e.g. the movement
    /// trigger's exit re-delivered after its pass re-centred the trigger). By state it is a new
    /// crossing; by date it is older than the last event processed, and refused on that.
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
            // The OS hands the first event over again, unchanged.
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
            // Every captured record must carry `ev`, or the matcher has nothing to align on.
            #expect(harness.emitted.allSatisfy { $0["ev"] != nil })
        }
    }

    /// A second adopt in one process re-arms nothing.
    ///
    /// The bootstrap re-runs on reconcile drift and permission changes, adopting from storage read
    /// before in-flight work lands. Re-arming there can include just-evicted conditions, push the
    /// OS over its budget, and make CoreLocation give every condition up.
    @Test
    @available(iOS 17.0, *)
    func wireMonitor_givenAlreadyAdopted_expectSecondRunRearmsNothing() async throws {
        try await ReplayHarness.withTail {
            let harness = ReplayHarness()
            try await registered(harness, fenceId: "A")

            // Counted before the relaunch: the double survives `reenterProcess()` and already holds
            // setup's operations.
            let armedBeforeRelaunch = harness.conditionMonitor.operations.count

            // The OS relaunches the app: the mirror says both conditions survived, so the bootstrap adopts.
            harness.reenterProcess()
            await harness.wireMonitor()
            try await harness.settleBoundaries()
            _ = await settleOnMain { harness.emitted(ev: "registration.adopted").count == 1 }
            let armedOnce = harness.conditionMonitor.operations.count
            #expect(armedOnce > armedBeforeRelaunch, "the first adopt re-armed nothing")

            // Reconcile drift, a permission change — any second run in the same process.
            await harness.wireMonitor()
            try await harness.settleBoundaries()

            #expect(harness.emitted(ev: "registration.adopted").count == 1, "the second run adopted again")
            #expect(harness.conditionMonitor.operations.count == armedOnce, "the second run drove the OS: \(harness.conditionMonitor.operations[armedOnce...])")
        }
    }
}
