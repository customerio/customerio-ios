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

/// Drives the real `CLMonitor` wrapper; only CoreLocation is faked.
@Suite("CLMonitor relaunch behaviour", .serialized, .enabled(if: monitorAvailable))
@MainActor
struct CLMonitorRelaunchTests {
    private static let center = LocationData(latitude: 10, longitude: 20)
    /// About 3 km from `center`: unambiguously a different circle.
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

    /// `preloaded` conditions are already at the OS, as a relaunched process finds them.
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
        // Nothing is meaningful until the initial OS reconcile and the async events subscriber have
        // run.
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

    /// Diagnostics must be on BEFORE the wrapper is built: the gate is a task-local its `init`
    /// Tasks inherit. `body` is `@MainActor`: an off-actor read of the OS double has crashed the
    /// test process.
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

            fixture.monitor.adoptExistingRegions(matching: ["f1", "f2"], records: records)
            await settleQuietly()

            #expect(
                fixture.os.operations == afterFirst,
                "a second adopt drove the OS again: \(fixture.os.operations.dropFirst(afterFirst.count))"
            )
            #expect(tails(fixture, ev: "registration.adopted").count == 1)
        }
    }

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

    @Test
    @available(iOS 17.0, *)
    func adoptExistingRegions_givenRecordDisagreesWithStagedGeometry_expectSkipped() async {
        await withFixture(preloaded: ["f1": .unsatisfied]) { fixture in
            await fixture.storage.recordMonitorRegistration(
                identifier: "f1", transitionTypes: [.enter, .exit],
                initialState: .exit, center: Self.center, radius: Self.radius
            )
            // The caller stages a different circle, as a mid-flight reshape would.
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

    /// On relaunch the OS re-emits current state before older queued events. The re-emission must still
    /// advance the stored OS date so the older copy is refused as a redelivery.
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

            fixture.os.deliver(identifier: "f1", state: .unsatisfied, at: reEmittedAt)
            _ = await settleOnMain { tails(fixture, ev: "os.callback.dropped").count == 1 }
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

    /// A wake-sized trigger is small enough that a real exit arrives while the cached fix still
    /// reads the centre; gating it would refuse the crossing that drives the next polygon pass.
    @Test
    @available(iOS 17.0, *)
    func movementTriggerExit_givenFixAtTheCentreRightAfterTheAdd_expectDelivered() async {
        await withFixture { fixture in
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
            // Wait for delivery, not a bare settle, so a re-gated trigger fails instead of passing
            // early.
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
