@testable import CioInternalCommon
@testable import CioLocationGeofence
import CoreLocation
import Foundation
import SharedTests
import Testing

private let monitorAvailable: Bool = {
    if #available(iOS 17.0, *) { return true }
    return false
}()

/// The relaunch behaviour of the `CLMonitor` wrapper, driven through the OS seams.
///
/// **Why these exist.** A field drive on 2026-09-12 recorded a cold relaunch after which the SDK
/// delivered four events for a fence the device was kilometres outside, then stopped monitoring
/// entirely for 66 minutes. Five defects chained together to do that, and every one of them lives
/// in this wrapper — in the order operations drain, not in any single decision. None was reachable
/// by a test until `GeofenceOSSeams` made `CLMonitor` substitutable.
///
/// The wrapper itself is never substituted here: only CoreLocation is.
@Suite("CLMonitor relaunch behaviour", .serialized, .enabled(if: monitorAvailable))
@MainActor
struct CLMonitorRelaunchTests {
    private static let center = LocationData(latitude: 10, longitude: 20)
    /// About 3 km from `center`, so a record naming one and a registration naming the other are
    /// unambiguously different circles.
    private static let otherCenter = LocationData(latitude: 10.02, longitude: 20.02)
    private static let radius: Double = 250

    @available(iOS 17.0, *)
    private struct Fixture {
        let monitor: CLMonitorGeofenceMonitor
        let os: FakeConditionMonitor
        let authority: FakeLocationAuthority
        let storage: GeofenceStorage
        let logger: CapturingLogger
        let clock: DateUtilStub
        let directory: URL
        let defaultsSuite: String
    }

    /// Builds the real wrapper on the doubles, with the conditions `preloaded` already at the OS —
    /// which is what a process relaunched by the OS finds.
    @available(iOS 17.0, *)
    private func makeFixture(preloaded: [String: GeofenceConditionState] = [:]) async -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("geofence-relaunch-\(UUID().uuidString)")
        let defaultsSuite = "io.customer.test.geofence.\(UUID().uuidString)"
        let clock = DateUtilStub()
        clock.givenNow = Date(timeIntervalSince1970: 1789215000)
        let logger = CapturingLogger()
        let storage = GeofenceStorage(directoryURL: directory, dateUtil: clock)
        let os = FakeConditionMonitor()
        for (identifier, assumed) in preloaded {
            os.preload(identifier: identifier, center: Self.center, radius: Self.radius, assuming: assumed)
        }
        let authority = FakeLocationAuthority()
        let monitor = CLMonitorGeofenceMonitor(
            logger: logger,
            storage: storage,
            userDefaults: UserDefaults(suiteName: defaultsSuite) ?? .standard,
            dateUtil: clock,
            authority: authority,
            makeConditionMonitor: { [os] _ in os }
        )
        // The wrapper's first pipeline operation reconciles against the OS's persisted truth, and
        // its events consumer attaches asynchronously. Nothing a test does is meaningful until both
        // have run.
        _ = await settleOnMain { os.hasSubscriber && monitor.osMonitoredRegionIdentifiers.count == preloaded.count }
        return Fixture(
            monitor: monitor, os: os, authority: authority, storage: storage,
            logger: logger, clock: clock, directory: directory, defaultsSuite: defaultsSuite
        )
    }

    @available(iOS 17.0, *)
    private func cleanUp(_ fixture: Fixture) {
        try? FileManager.default.removeItem(at: fixture.directory)
        UserDefaults.standard.removePersistentDomain(forName: fixture.defaultsSuite)
    }

    /// Runs `body` against a fresh fixture with the diagnostic tail on for the whole of it.
    ///
    /// The gate must be open **before** the wrapper is built. It is a task-local, and the wrapper's
    /// events consumer and its operation pipeline are `Task`s started in `init` — they inherit the
    /// value in scope at that moment. Opening the gate afterwards leaves every record those tasks
    /// emit without a machine tail, which reads in a test exactly like the SDK deciding nothing.
    ///
    /// `body` is `@MainActor` on purpose. The wrapper and both doubles are main-actor isolated, so a
    /// body that ran anywhere else would read their state off-actor — which is not a theoretical
    /// hazard: an unguarded poll of the OS double's dictionary tore a read and killed the whole test
    /// process with `-[__NSCFNumber objectForKey:]`. Awaiting a main-actor member from the
    /// non-isolated closure below hops there, and task-locals survive the hop, so the gate stays open.
    @available(iOS 17.0, *)
    private func withFixture(
        preloaded: [String: GeofenceConditionState] = [:],
        _ body: @MainActor (Fixture) async -> Void
    ) async {
        await DiagnosticsGateTesting.withDiagnostics(true) {
            let fixture = await makeFixture(preloaded: preloaded)
            await body(fixture)
            await cleanUp(fixture)
        }
    }

    @available(iOS 17.0, *)
    private func tails(_ fixture: Fixture, ev: String) -> [[String: String]] {
        GeofenceTail.parseAll(fixture.logger.messages).filter { $0["ev"] == ev }
    }

    // MARK: - A second adopt in one process

    /// **The root of the 2026-09-12 cascade.**
    ///
    /// `GeofenceBootstrap` re-runs on mirror drift and on every authorization change, and each run
    /// that finds the OS still holding its expected set calls this. The second run read storage
    /// before an in-flight sync's writes had landed, re-armed the previous set — two of whose
    /// conditions that sync had just evicted, their removes still queued ahead — and left the OS
    /// holding more than the platform allows. CoreLocation then gave up nineteen of them.
    @Test
    @available(iOS 17.0, *)
    func adoptExistingRegions_givenAlreadyAdoptedInThisProcess_expectNoSecondRearm() async {
        await withFixture(preloaded: ["f1": .unsatisfied, "f2": .unsatisfied]) { fixture in
            for identifier in ["f1", "f2"] {
                await fixture.storage.recordMonitorRegistration(
                    identifier: identifier, transitionTypes: [.enter, .exit],
                    initialState: .exit, center: Self.center, radius: Self.radius
                )
            }
            let records = await fixture.storage.getMonitorRegionRecords()

            fixture.monitor.adoptExistingRegions(matching: ["f1", "f2"], records: records)
            _ = await settleOnMain { fixture.os.operations.count == 4 }
            let afterFirst = fixture.os.operations
            #expect(afterFirst.count == 4, "first adopt should remove and re-add each condition: \(afterFirst)")

            // Mirror drift, a permission change — any second run in the same process.
            fixture.monitor.adoptExistingRegions(matching: ["f1", "f2"], records: records)
            await settleQuietly()

            #expect(
                fixture.os.operations == afterFirst,
                "a second adopt drove the OS again: \(fixture.os.operations.dropFirst(afterFirst.count))"
            )
            #expect(tails(fixture, ev: "registration.adopted").count == 1)
        }
    }

    /// A relaunch that adopts and re-arms has to say what the OS ended up holding.
    ///
    /// `registration.applied` is the only record that answers "was this fence being watched", and
    /// it used to be emitted solely by the sync coordinator — which the adopt path never reaches.
    /// A relaunch that adopted twenty conditions and did nothing else produced no output record at
    /// all, so a replay of it graded nothing. That is why the second-adopt defect above was
    /// invisible to the harness until it was written as a direct test.
    ///
    /// Read from the OS, not from the set we asked for: the re-arm skips any condition whose stored
    /// geometry no longer matches, so the two can differ.
    @Test
    @available(iOS 17.0, *)
    func adoptExistingRegions_expectTheHeldSetReported() async {
        await withFixture(preloaded: ["f1": .unsatisfied, "f2": .unsatisfied]) { fixture in
            for identifier in ["f1", "f2"] {
                await fixture.storage.recordMonitorRegistration(
                    identifier: identifier, transitionTypes: [.enter, .exit],
                    initialState: .exit, center: Self.center, radius: Self.radius
                )
            }
            let records = await fixture.storage.getMonitorRegionRecords()

            fixture.monitor.adoptExistingRegions(matching: ["f1", "f2"], records: records)
            _ = await settleOnMain { !tails(fixture, ev: "registration.applied").isEmpty }
            await settleQuietly()

            let applied = tails(fixture, ev: "registration.applied")
            #expect(applied.count == 1, "adopt emitted \(applied.count) registration.applied records")
            #expect(applied.last?["ids"] == "f1,f2", "reported ids: \(applied.last?["ids"] ?? "none")")
            #expect(applied.last?["n"] == "2")
        }
    }

    /// Adoption is also refused for a condition this process no longer owns — a sync that dropped
    /// it has its remove queued, and re-adding it here would resurrect the region behind that.
    @Test
    @available(iOS 17.0, *)
    func adoptExistingRegions_givenConditionNoLongerOwned_expectNotReadded() async {
        await withFixture(preloaded: ["f1": .unsatisfied]) { fixture in
            await fixture.storage.recordMonitorRegistration(
                identifier: "f1", transitionTypes: [.enter, .exit],
                initialState: .exit, center: Self.center, radius: Self.radius
            )
            let records = await fixture.storage.getMonitorRegionRecords()
            fixture.monitor.stopMonitoring(identifier: "f1")
            _ = await settleOnMain { fixture.os.held["f1"] == nil }
            fixture.os.resetOperations()

            fixture.monitor.adoptExistingRegions(matching: ["f1"], records: records)
            await settleQuietly()

            #expect(fixture.os.operations.isEmpty, "a released condition was adopted back: \(fixture.os.operations)")
        }
    }

    // MARK: - The re-arm reads state when it drains

    /// The re-arm asserts a state to the OS, and that state must be the one storage holds when the
    /// operation runs. It used to be a snapshot taken when the bootstrap started: on the drive the
    /// movement trigger was re-added asserting "inside" thirty milliseconds after its exit had been
    /// accepted, and the daemon answered with a corrective the dedup then had to absorb.
    @Test
    @available(iOS 17.0, *)
    func adoptExistingRegions_expectRearmAssertsTheStoredState() async {
        await withFixture(preloaded: ["f1": .unsatisfied]) { fixture in
            await fixture.storage.recordMonitorRegistration(
                identifier: "f1", transitionTypes: [.enter, .exit],
                initialState: .enter, center: Self.center, radius: Self.radius
            )
            let records = await fixture.storage.getMonitorRegionRecords()

            fixture.monitor.adoptExistingRegions(matching: ["f1"], records: records)
            _ = await settleOnMain { fixture.os.held["f1"]?.assumed == .satisfied }

            #expect(fixture.os.held["f1"]?.assumed == .satisfied, "the re-arm did not assert the stored state")
        }
    }

    /// And a condition whose stored record disagrees with the staged registration is skipped
    /// rather than re-armed from either snapshot: a sync reshaping it has its own add queued
    /// behind this one, and imposing the old circle here would leave the two bookkeeping layers
    /// permanently disagreeing about what the OS holds.
    @Test
    @available(iOS 17.0, *)
    func adoptExistingRegions_givenRecordDisagreesWithStagedGeometry_expectSkipped() async {
        await withFixture(preloaded: ["f1": .unsatisfied]) { fixture in
            // Storage holds one circle...
            await fixture.storage.recordMonitorRegistration(
                identifier: "f1", transitionTypes: [.enter, .exit],
                initialState: .exit, center: Self.center, radius: Self.radius
            )
            // ...while the caller stages a different one, as a mid-flight reshape would.
            let stale = [
                "f1": MonitorRegionRecord(
                    lastState: .exit, transitionTypes: [.enter, .exit],
                    center: Self.otherCenter, radius: Self.radius
                )
            ]
            fixture.os.resetOperations()

            fixture.monitor.adoptExistingRegions(matching: ["f1"], records: stale)
            await settleQuietly()

            #expect(fixture.os.operations.isEmpty, "a mid-reshape condition was re-armed: \(fixture.os.operations)")
        }
    }

    // MARK: - The OS giving a condition up

    /// **The spurious events.**
    ///
    /// `handleConditionUnmonitored` wipes the contradiction-gate stamp and the geometry record
    /// synchronously, but clears the stored dedup baseline from the serial operation queue, behind
    /// every OS call already pending. In that window the condition has no gate and a baseline that
    /// still reads "outside", and the daemon replays its belief: on the drive a fence the device was
    /// ranked 4.5 km outside was delivered as four customer events, one millisecond after its own
    /// unmonitored notice.
    ///
    /// The OS is held here so the clear really is still queued when the replay lands. Let it drain
    /// first and the event is refused for having no baseline at all — the right outcome reached by
    /// luck, which passes with or without the fix and so proves nothing.
    @Test
    @available(iOS 17.0, *)
    func unmonitoredCondition_givenReplayBeforeTheBaselineClearDrains_expectNotDelivered() async {
        await withFixture(preloaded: ["f1": .unsatisfied]) { fixture in
            await fixture.storage.recordMonitorRegistration(
                identifier: "f1", transitionTypes: [.enter, .exit],
                initialState: .exit, center: Self.center, radius: Self.radius
            )
            let delivered = DeliveredTransitions()
            fixture.monitor.setOnTransition { identifier, transition, _, _, _, _ in
                delivered.record(identifier, transition)
            }
            fixture.monitor.setOnReconciled {}

            // An OS call that has not come back yet; everything queued after it stays queued.
            fixture.os.holdOperations()
            fixture.monitor.startMonitoring(
                identifier: "f2", center: Self.otherCenter, radius: Self.radius, transitionTypes: [.enter, .exit]
            )
            _ = await settleOnMain { fixture.os.hasParkedOperation }

            fixture.os.deliver(identifier: "f1", state: .unmonitored, at: fixture.clock.now)
            fixture.os.deliver(identifier: "f1", state: .satisfied, at: fixture.clock.now)
            _ = await settleOnMain { !tails(fixture, ev: "os.callback.dropped").isEmpty }
            await settleQuietly()

            #expect(delivered.isEmpty, "a dead condition's replay was delivered: \(delivered.description)")
            #expect(tails(fixture, ev: "os.callback.dropped").first?["why"] == "awaiting_reregistration")

            fixture.os.releaseOperations()
            await settleQuietly()
        }
    }

    /// **The outage.**
    ///
    /// The handler left re-registration to "the next sync", and syncs are driven by the movement
    /// trigger — itself a monitored condition. On the drive the trigger was among the twenty the OS
    /// gave up, so no sync could come: the phone drove 4.2 km over the next 66 minutes with the
    /// module frozen and two fences' crossings lost, until a sign-out reset it.
    @Test
    @available(iOS 17.0, *)
    func unmonitoredCondition_expectReregistrationScheduled() async {
        await withFixture(preloaded: ["f1": .unsatisfied]) { fixture in
            await fixture.storage.recordMonitorRegistration(
                identifier: "f1", transitionTypes: [.enter, .exit],
                initialState: .exit, center: Self.center, radius: Self.radius
            )
            fixture.monitor.setOnTransition { _, _, _, _, _, _ in }
            var reconciled = 0
            fixture.monitor.setOnReconciled { reconciled += 1 }

            fixture.os.deliver(identifier: "f1", state: .unmonitored, at: fixture.clock.now)
            _ = await settleOnMain { reconciled >= 1 }
            await settleQuietly()

            #expect(reconciled == 1, "re-registration was not scheduled")
            #expect(tails(fixture, ev: "registration.recovery").count == 1)
        }
    }

    /// One recovery per burst. A storm of twenty conditions given up at once must not schedule
    /// twenty bootstrap re-runs.
    @Test
    @available(iOS 17.0, *)
    func unmonitoredConditions_givenABurst_expectOneRecovery() async {
        let identifiers = (1 ... 5).map { "f\($0)" }
        let preloaded = Dictionary(uniqueKeysWithValues: identifiers.map { ($0, GeofenceConditionState.unsatisfied) })
        await withFixture(preloaded: preloaded) { fixture in
            for identifier in identifiers {
                await fixture.storage.recordMonitorRegistration(
                    identifier: identifier, transitionTypes: [.enter, .exit],
                    initialState: .exit, center: Self.center, radius: Self.radius
                )
            }
            fixture.monitor.setOnTransition { _, _, _, _, _, _ in }
            var reconciled = 0
            fixture.monitor.setOnReconciled { reconciled += 1 }

            for identifier in identifiers {
                fixture.os.deliver(identifier: identifier, state: .unmonitored, at: fixture.clock.now)
            }
            _ = await settleOnMain { reconciled >= 1 }
            await settleQuietly()

            #expect(reconciled == 1, "a burst scheduled \(reconciled) recoveries")
            #expect(tails(fixture, ev: "registration.recovery").count == 1)
        }
    }

    // MARK: - Event identity, not the SDK's write time

    /// CoreLocation hands the same event over two or three times, not always in date order, and on
    /// a relaunch it re-emits every condition's current state before the older events it still
    /// holds. A copy dated at or before one already processed is a copy, whatever state it carries.
    ///
    /// The rule used to be the SDK's own write time against the OS's clock. A re-emission changes
    /// no state, so it wrote nothing — leaving the stored stamp at registration time, which the
    /// older event that followed comfortably post-dated. It read as new, and was delivered as a
    /// crossing the device never made.
    @Test
    @available(iOS 17.0, *)
    func osEvent_givenOlderCopyAfterAReEmission_expectRefused() async {
        await withFixture(preloaded: ["f1": .unsatisfied]) { fixture in
            await fixture.storage.recordMonitorRegistration(
                identifier: "f1", transitionTypes: [.enter, .exit],
                initialState: .exit, center: Self.center, radius: Self.radius
            )
            let delivered = DeliveredTransitions()
            fixture.monitor.setOnTransition { identifier, transition, _, _, _, _ in
                delivered.record(identifier, transition)
            }
            let reEmittedAt = fixture.clock.now.addingTimeInterval(300)

            // The daemon re-emitting the state the SDK already holds: nothing to deliver.
            fixture.os.deliver(identifier: "f1", state: .unsatisfied, at: reEmittedAt)
            _ = await settleOnMain { tails(fixture, ev: "os.callback.dropped").count == 1 }
            // ...then an older copy of the other state, queued behind it.
            fixture.os.deliver(identifier: "f1", state: .satisfied, at: reEmittedAt.addingTimeInterval(-60))
            _ = await settleOnMain { tails(fixture, ev: "os.callback.dropped").count == 2 }
            await settleQuietly()

            #expect(delivered.isEmpty, "a superseded copy was delivered as a crossing: \(delivered.description)")
            #expect(
                tails(fixture, ev: "os.callback.dropped").map { $0["why"] } == ["no_state_change", "redelivered"]
            )
        }
    }

    // MARK: - The movement trigger is gated like any other condition

    /// It is added centred on the device, so an exit the daemon dates within seconds of that add is
    /// its stale belief replayed, never a kilometre of displacement. The trigger used to be exempt
    /// from the contradiction gate, and a replay it accepted drove a whole redundant sync pass —
    /// which re-registers conditions, which provokes more correctives.
    @Test
    @available(iOS 17.0, *)
    func movementTriggerExit_givenFixAtTheCentreRightAfterTheAdd_expectRefused() async {
        await withFixture { fixture in
            // The device sits at the trigger's centre, and the read is fresh.
            fixture.authority.answerCachedLocation = { [clock = fixture.clock] in
                CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: Self.center.latitude, longitude: Self.center.longitude),
                    altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10,
                    timestamp: clock.now
                )
            }
            let delivered = DeliveredTransitions()
            fixture.monitor.setOnTransition { identifier, transition, _, _, _, _ in
                delivered.record(identifier, transition)
            }

            fixture.monitor.startMonitoring(
                identifier: GeofenceConstants.movementTriggerIdentifier,
                center: Self.center, radius: 1000, transitionTypes: [.exit]
            )
            _ = await settleOnMain { fixture.os.held[GeofenceConstants.movementTriggerIdentifier] != nil }

            fixture.os.deliver(
                identifier: GeofenceConstants.movementTriggerIdentifier,
                state: .unsatisfied, at: fixture.clock.now
            )
            _ = await settleOnMain { !tails(fixture, ev: "contradiction.refused").isEmpty }

            #expect(
                tails(fixture, ev: "contradiction.refused").first?["id"] == GeofenceConstants.movementTriggerIdentifier
            )
            #expect(delivered.isEmpty, "a belief replay started a movement pass: \(delivered.description)")
        }
    }
}
