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

/// The relaunch behaviour of the `CLMonitor` wrapper, driven through the OS seams. These guard
/// against a cold relaunch delivering events for a fence kilometres away and then losing
/// monitoring; the defects live in the order operations drain, not in any single decision.
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
    /// The gate must be open **before** the wrapper is built: it is a task-local, and the wrapper's
    /// events consumer and operation pipeline are `Task`s started in `init` that inherit it then.
    ///
    /// `body` is `@MainActor` because the wrapper and both doubles are main-actor isolated; an
    /// off-actor read of the OS double has crashed the test process. Task-locals survive the hop.
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

    /// `GeofenceBootstrap` re-runs adopt on reconcile drift and on authorization changes, from
    /// storage read before in-flight sync writes land. A second re-arm can re-add conditions a
    /// sync just evicted and push the OS over its condition budget.
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

    /// Adopt never reaches the sync coordinator, so it must emit `registration.applied` itself.
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

    /// The re-arm asserts the state storage holds when the operation drains, not a snapshot from
    /// when it was staged: a crossing accepted in between would otherwise be contradicted at the
    /// OS, and the daemon answers with a corrective the dedup has to absorb.
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

    /// A condition whose stored record disagrees with the staged registration is skipped
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

    // MARK: - Event identity, not the SDK's write time

    /// CoreLocation hands the same event over more than once, not always in date order, and on a
    /// relaunch re-emits every condition's current state before the older events it still holds.
    /// A re-emission changes no state but must still advance the stored OS date, so the older copy
    /// behind it is refused as a redelivery rather than delivered as a crossing.
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

    // MARK: - The movement trigger is exempt from the contradiction gate

    /// Polygon wake-sizing shrinks the trigger to `polygonWakeMinRadius`, so a genuine exit lands
    /// inside the gate's window (a moving car covers 100 m well under 10 s) while the cached fix
    /// still reads the centre. Gating it would refuse the crossing that drives the next polygon pass.
    @Test
    @available(iOS 17.0, *)
    func movementTriggerExit_givenFixAtTheCentreRightAfterTheAdd_expectDelivered() async {
        await withFixture { fixture in
            // The cached fix still reads the trigger's centre: the shape the gate refuses for a
            // business circle.
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
                center: Self.center, radius: GeofenceConstants.polygonWakeMinRadius, transitionTypes: [.exit]
            )
            _ = await settleOnMain { fixture.os.held[GeofenceConstants.movementTriggerIdentifier] != nil }

            fixture.os.deliver(
                identifier: GeofenceConstants.movementTriggerIdentifier,
                state: .unsatisfied, at: fixture.clock.now
            )
            // Positive signal: the movement pass delivered the exit. Waiting for this (not a bare
            // settle) means a regression that re-gates the trigger fails here rather than passing
            // because nothing had run yet.
            let wasDelivered = await settleOnMain {
                delivered.all.contains { $0.identifier == GeofenceConstants.movementTriggerIdentifier && $0.transition == .exit }
            }

            #expect(wasDelivered, "the movement trigger exit was refused, not delivered: \(delivered.description)")
            #expect(
                tails(fixture, ev: "contradiction.refused").isEmpty,
                "the movement trigger was sent through the gate: \(tails(fixture, ev: "contradiction.refused"))"
            )
        }
    }
}
