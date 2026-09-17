@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import SharedTests
import Testing

/// The composition produces real SDK decisions from injected input.
///
/// These are the harness's own tests, not a drive's: they prove the SDK can be driven without a
/// device, without the OS, and on a clock the test controls. A scenario replay only means
/// something if this holds first.
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
    /// Past `contradictionGateReplayWindow` (10 s) deliberately. Inside that window the SDK vets an
    /// OS event against a fresh fix, because a CLMonitor re-add replays the daemon's stale belief as
    /// an immediate event — so a crossing delivered in the same instant as the registration, with
    /// the device still parked outside, is one the SDK is *right* to refuse. Registering and then
    /// teleporting into the fence is not something a drive can do; arriving a while later is.
    private static let arrivalAt: TimeInterval = 30

    /// One fence, as the API would return it.
    private func catalogue(_ fenceId: String) -> String {
        """
        [{"id":"\(fenceId)","name":"F","latitude":\(Self.latitude),"longitude":\(Self.longitude),"radius":250,"transitionTypes":["enter","exit"],"geosetIds":["7"]}]
        """
    }

    /// Brings the SDK to a registered state the only way a real app can: answer its fetch, give it
    /// a position, sign a user in. Nothing is written to the SDK's own state by the test — the
    /// registration, and the dedup baseline behind it, are the SDK's own work.
    @available(iOS 17.0, *)
    private func registered(_ harness: ReplayHarness, fenceId: String) async throws {
        try harness.enqueueFetch(bodyJSON: catalogue(fenceId))
        // A `manager_cache` position is something the SDK *pulls*, so it is loaded as the cache's
        // value from t0 rather than delivered as an event. Handing it over as a stimulus would
        // model a fix arriving, which is not what reading `CLLocationManager.location` is.
        harness.loadPulledFixes(stimuli: [0, Self.arrivalAt], samples: [
            harness.pulledFix(
                latitude: Self.awayLatitude,
                longitude: Self.longitude,
                accuracy: 10,
                age: 0,
                at: 0
            ),
            // Where the device is once it has driven in. The SDK reads this — it is not told it —
            // so every decision that follows sees the position a phone at the fence would report.
            harness.pulledFix(
                latitude: Self.latitude,
                longitude: Self.longitude,
                accuracy: 10,
                age: 0,
                at: Self.arrivalAt
            )
        ])
        harness.setIdentified(true)
        // `onIdentified` runs its anchor decision on a Task, and with no anchor available it arms
        // for the next fix — in `.automatic` that arming is what calls `acquireFix`. Waiting on the
        // call makes the arm observable: feeding the bus fix before it lands means `onLocationAcquired`
        // sees nothing armed, drops the fix, and no sync ever starts. The old harness hid this race
        // by caching bus fixes as the module's last-known, which gave the Task an anchor it should
        // not have had (see `feedFix`).
        #expect(
            await settleOnMain { harness.acquireFixCallCount >= 1 },
            "identify did not arm for a fix"
        )
        // What actually drives the sync: a fix *arriving* from the Location module. The pull above
        // only answers the reads the registration ledger makes once the sync is already running —
        // it cannot start one, because production's trigger reads the Location module's stored
        // position, not the geofence monitor's cache.
        harness.feedFix(
            latitude: Self.awayLatitude,
            longitude: Self.longitude,
            accuracy: nil,
            age: 0,
            source: .bus
        )
        // The fetch and the baseline write are boundaries now: they answer when the drive says
        // they did, and a hand-written setup has no drive behind it. See `settleBoundaries`.
        try await harness.settleBoundaries()
        #expect(
            await settleOnMain { harness.emitted(ev: "registration.applied").count == 1 },
            "setup did not reach a registered state: \(harness.emitted.map { $0["ev"] ?? "?" })"
        )
        // The drive in. Until now the fence is registered and the device is outside it; from here
        // the cache answers with the fence's own coordinates, which is what makes an arriving
        // `enter` agree with the world instead of contradicting it.
        await harness.advance(to: Self.arrivalAt)
        harness.resetOutput()
    }

    /// A `prov=resolver` record is the SDK *reading* its own cache, not a position arriving.
    ///
    /// `bestKnownFixDetail()` writes one whenever the resolver's fix is newer than
    /// `CLLocationManager`'s, and nothing about that read reaches `GeofenceRefreshTrigger` — only
    /// the Location module's bus event does. Replaying it as a delivery consumed the rearm flag
    /// identify had just set and started a sync the drive never ran.
    ///
    /// The bus fix at the end is the control. Without it a harness that had stopped delivering
    /// *any* fix would pass the first half of this test having proved nothing.
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

    /// **The spike's central assumption.**
    ///
    /// §5 of the format decision claims the iOS clock gap does not block replay, because the raw
    /// `Date()` sites live in the CLMonitor wrappers that replay substitutes. If that is wrong, the
    /// cooldown below is computed against wall-clock time while the scenario is stamped in virtual
    /// time, and every duration assertion in the scenarios becomes meaningless *while still passing*.
    ///
    /// Rather than grep for `Date()`, this drives the real cooldown path and checks the decision
    /// follows virtual time.
    ///
    /// Each `enter` is preceded by an `exit` so it is a genuine state change. Without that the
    /// dedup baseline discards it as a duplicate and the cooldown is never consulted — the test
    /// would pass having proved nothing. Cooldown is keyed per `user:fence:transition`, so the
    /// interleaved exits do not consume the enter's window.
    ///
    /// Every crossing gets its own instant. An OS event's identity is its date, and two events for
    /// one condition sharing a date are one event delivered twice — on a phone the daemon cannot
    /// date an enter and an exit of the same condition identically. Delivering two at one virtual
    /// instant would therefore model a re-delivery, and the second would be refused as one.
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
                // A crossing can re-centre the movement trigger, and the baseline write that
                // follows is a boundary now. A replayed drive opens it from the recording; this
                // test has no recording, so it says so explicitly. Without it the write stays owed
                // and the next crossing is judged against the previous centre.
                try await harness.settleBoundaries()
                await settleOnMain { harness.emitted(ev: "transition.accepted").count > accepted }
            }

            try await cross(.enter, at: Self.arrivalAt + 1)
            #expect(harness.emitted(ev: "transition.accepted").contains { $0["t"] == "enter" })
            try await cross(.exit, at: Self.arrivalAt + 2)

            // Still inside the enter cooldown in *virtual* time. Only milliseconds of real time have
            // passed, so a wall-clock read would also suppress here — this leg alone proves nothing.
            // It is the pair that does.
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

    /// **The re-delivery rule, exercised.**
    ///
    /// CoreLocation hands the same event over more than once — byte-identical objects sharing a
    /// microsecond `date`. Two deliveries at one virtual instant model that exactly, because the
    /// harness dates an event from the clock at delivery. The record remembers the date of the last
    /// event it processed, so the copy is refused by identity, before its state is even compared.
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

    /// The other half: a genuinely different event must not be swallowed. Advancing the clock gives
    /// the second crossing its own date, which is what a real later crossing always carries.
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

    /// The case the state compare alone cannot see: a copy of an *earlier* event arriving after the
    /// baseline has moved on. On the road this is the movement trigger's exit re-delivered after the
    /// pass it started re-centred the trigger; the copy's state differs from the fresh seed, so by
    /// state alone it is a new crossing. By date it is older than the last event processed for the
    /// condition, and refused on that — not on when the SDK happened to write the baseline, which
    /// is the comparison that answered differently on the phone and in replay (drive 5).
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
            // Every captured record must carry the replay classification, or the matcher has nothing
            // to align on.
            #expect(harness.emitted.allSatisfy { $0["ev"] != nil })
        }
    }

    /// **The OS giving a condition up, end to end.** (drive 5, 2026-09-12)
    ///
    /// Two things must hold from the instant `.unmonitored` arrives, not from whenever the queue
    /// gets round to it. An event for the condition is refused outright — the phone judged one
    /// against the stale baseline 1 ms after the `.unmonitored`, with the queued clear still in
    /// flight, and delivered a fence 4.5 km away four times over. And a re-registration is
    /// scheduled by the SDK itself — the phone waited for "the next sync", which is driven by the
    /// movement trigger, which was among the conditions given up, and stayed frozen for an hour.
    @Test
    @available(iOS 17.0, *)
    func deliverMonitorStopped_givenArmedFence_expectEventsRefusedUntilReregistered() async throws {
        try await ReplayHarness.withTail {
            let harness = ReplayHarness()
            try await registered(harness, fenceId: "A")
            // The recovery route is the bootstrap's own re-run handler, which the bootstrap installs.
            // Production runs it at module init; the recorded suite runs it on `module.init`; a
            // hand-driven test has to run it once. The run itself adopts nothing new.
            await harness.wireMonitor()
            try await harness.settleBoundaries()
            harness.resetOutput()

            harness.deliverMonitorStopped(fence: "A")
            // The replay of a dead incarnation, landing right behind the `.unmonitored`.
            harness.deliverCrossing(fence: "A", transition: .enter)
            try await harness.settleBoundaries()
            await settleOnMain { harness.emitted(ev: "registration.applied").count == 1 }

            #expect(harness.emitted(ev: "transition.accepted").isEmpty, "a dead condition's replay was delivered")
            let dropped = harness.emitted(ev: "os.callback.dropped")
            #expect(dropped.count == 1)
            #expect(dropped.first?["why"] == "awaiting_reregistration")
            // The SDK re-registered the condition on its own, and only that one.
            #expect(harness.emitted(ev: "registration.recovery").count == 1)
            let diff = harness.emitted(ev: "registration.diff").first
            #expect(diff?["nadd"] == "1" && diff?["nrem"] == "0", "diff: \(String(describing: diff))")
            #expect(harness.conditionMonitor.held["A"] != nil, "the OS was not handed the condition back")
        }
    }

    /// **The movement trigger is gated like any other condition.** (drive 5, 2026-09-12)
    ///
    /// It is added centred on the device, so an exit the daemon dates within seconds of that add
    /// is its stale belief replayed, not a kilometre of displacement — the phone absorbed one such
    /// replay only because its queue happened to drain after the daemon dated it. The gate reads a
    /// fresh position, finds the device at the centre, and refuses the exit before any baseline is
    /// consulted, so no movement pass starts.
    @Test
    @available(iOS 17.0, *)
    func deliverCrossing_givenTriggerExitReplayedRightAfterItsAdd_expectRefused() async throws {
        try await ReplayHarness.withTail {
            let harness = ReplayHarness()
            try await registered(harness, fenceId: "A")
            // The device is back at the trigger's centre when the gate reads a position.
            let later = Self.arrivalAt + 10
            harness.loadPulledFixes(stimuli: [0, Self.arrivalAt, later], samples: [
                harness.pulledFix(latitude: Self.awayLatitude, longitude: Self.longitude, accuracy: 10, age: 0, at: 0),
                harness.pulledFix(latitude: Self.latitude, longitude: Self.longitude, accuracy: 10, age: 0, at: Self.arrivalAt),
                harness.pulledFix(latitude: Self.awayLatitude, longitude: Self.longitude, accuracy: 10, age: 0, at: later)
            ])
            await harness.advance(to: later)
            harness.resetOutput()

            // Dated seconds after the trigger's add at t≈0: inside the replay window.
            harness.deliverCrossing(fence: GeofenceConstants.movementTriggerIdentifier, transition: .exit, identity: 5)
            try await harness.settleBoundaries()
            await settleOnMain { harness.emitted(ev: "contradiction.refused").count == 1 }

            #expect(harness.emitted(ev: "contradiction.refused").first?["id"] == GeofenceConstants.movementTriggerIdentifier)
            #expect(harness.emitted(ev: "movement.exit").isEmpty, "a refused replay started a movement pass")
            #expect(harness.emitted(ev: "registration.applied").isEmpty)
        }
    }

    /// **A second adopt in one process re-arms nothing.** (drive 5, 2026-09-12)
    ///
    /// The bootstrap re-runs on reconcile drift and on permission changes, and adopts again from
    /// storage read before in-flight work has landed. On the phone that second run re-armed the
    /// previous session's twenty conditions — two of them just evicted, their removes still queued
    /// ahead — put the OS over its budget, and CoreLocation gave every one of them up. Everything
    /// the first run adopted already has a geometry entry, so the second has nothing left to do.
    @Test
    @available(iOS 17.0, *)
    func wireMonitor_givenAlreadyAdopted_expectSecondRunRearmsNothing() async throws {
        try await ReplayHarness.withTail {
            let harness = ReplayHarness()
            try await registered(harness, fenceId: "A")

            // Counted before the relaunch: `registered()` has already driven the OS, and the double
            // is deliberately kept across `reenterProcess()`, so measuring after the adopt counts
            // setup's own operations and passes however little the adopt did.
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
