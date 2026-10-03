@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import Foundation
import SharedTests
import Testing

/// Through the real binder: every EXIT callback it notes is ended once its routing task is done,
/// whatever the resolver made of it, so no pending callback outlives its routing. The monitor
/// double delivers the callbacks; the executor runs the routing tasks. This checks the balance,
/// not the admission window, and is not physical callback acceptance.
@Suite("GeofenceExitCallbackBinder", .serialized)
@MainActor
struct GeofenceExitCallbackBinderTests {
    private static let circleId = "circle"
    /// The follow-up rig's circle: 150 m around (1, 2), dwell after 600 s.
    private static let circle = Geofence(
        id: circleId, latitude: 1, longitude: 2, radius: 150, name: "circle",
        transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1),
        dwellThresholdSeconds: 600
    )

    /// The same EXIT delivered twice is counted twice and cleared once both are routed.
    @Test
    func duplicateExitCallbacks_expectCountedAndCleared() async throws {
        let rig = await GeofenceDwellFollowupTests.Rig.make(insideFixAlways: true)
        await rig.cacheCircle()
        let monitor = MockGeofenceRegionMonitor()
        let resolver = Self.bind(monitor, to: rig)
        await rig.dwell.handleBoundary(geofence: Self.circle, transition: .enter, occurredAt: rig.clock.wall)
        rig.advance(600)
        let exitedAt = rig.clock.wall

        monitor.simulateTransition(identifier: Self.circleId, transition: .exit, location: nil, occurredAt: exitedAt)
        monitor.simulateTransition(identifier: Self.circleId, transition: .exit, location: nil, occurredAt: exitedAt)
        #expect(rig.dwell.pendingExitCallbacks[Self.circleId]?[exitedAt]?.count == 2)
        await settleQuietly(0.5)

        #expect(rig.dwell.pendingExitCallbacks.isEmpty)
        #expect(await rig.storage.getDwellVisit(geofenceId: Self.circleId) == nil)
        rig.dwell.cancelEvidence(for: Self.circleId)
        withExtendedLifetime(resolver) {}
    }

    /// Routings that record nothing still end their callback: an id the cache no longer holds, a
    /// user switch before the routing ran, and a resolver already released.
    @Test(arguments: ["uncached", "userChanged", "noResolver"])
    func exitCallbackRoutedToNothing_expectCleared(route: String) async throws {
        let rig = await GeofenceDwellFollowupTests.Rig.make(insideFixAlways: true)
        await rig.cacheCircle()
        let monitor = MockGeofenceRegionMonitor()
        var resolver: PolygonMembershipResolver? = Self.bind(monitor, to: rig)
        if route == "noResolver" { resolver = nil }
        let identifier = route == "uncached" ? "uncached" : Self.circleId

        monitor.simulateTransition(identifier: identifier, transition: .exit, location: nil, occurredAt: rig.clock.wall)
        #expect(rig.dwell.pendingExitCallbacks[identifier]?.count == 1)
        if route == "userChanged" { rig.contextStore.setUserId("user-2") }
        await settleQuietly(0.5)

        #expect(rig.dwell.pendingExitCallbacks.isEmpty)
        withExtendedLifetime(resolver) {}
    }

    /// The movement trigger's EXIT is not a fence's: it is never noted.
    @Test
    func movementTriggerExit_expectNotNoted() async throws {
        let rig = await GeofenceDwellFollowupTests.Rig.make(insideFixAlways: true)
        let monitor = MockGeofenceRegionMonitor()
        let resolver = Self.bind(monitor, to: rig)

        monitor.simulateTransition(
            identifier: GeofenceConstants.movementTriggerIdentifier, transition: .exit,
            location: LocationData(latitude: 1, longitude: 2), occurredAt: rig.clock.wall
        )
        #expect(rig.dwell.pendingExitCallbacks.isEmpty)
        await settleQuietly(0.3)
        #expect(rig.dwell.pendingExitCallbacks.isEmpty)
        withExtendedLifetime(resolver) {}
    }

    /// A polygon's covering-circle EXIT the resolver cannot decide (its circle expired) ends its
    /// callback, records no EXIT, and leaves the visit in place.
    @Test
    func undecidedCoveringExitThroughTheBinder_expectClearedAndTheVisitKept() async throws {
        let device = BootAmbiguityDevice()
        let process = await BootAmbiguityProcess(device: device)
        let polygon = BootAmbiguityDevice.polygon
        await process.pass()
        let stay = try #require(await process.visit())
        let monitor = MockGeofenceRegionMonitor()
        process.bind(monitor)
        device.advance(60)

        monitor.simulateTransition(
            identifier: polygon.id, transition: .exit, location: nil, occurredAt: device.clock.wall, eventCircle: .expired
        )
        #expect(process.dwell.pendingExitCallbacks[polygon.id]?.count == 1)
        await settleQuietly(0.5)

        #expect(process.dwell.pendingExitCallbacks.isEmpty)
        #expect(process.dwell.exitMarks[polygon.id] == nil)
        #expect(await process.visit() == stay)
        process.end()
    }

    // MARK: - Helpers

    /// Binds the monitor to the rig's coordinator through a real resolver, which the binder holds
    /// weakly: the caller keeps it alive, or releases it.
    private static func bind(_ monitor: MockGeofenceRegionMonitor, to rig: GeofenceDwellFollowupTests.Rig) -> PolygonMembershipResolver {
        let resolver = PolygonMembershipResolver(
            storage: rig.storage, transitionEmitter: rig.tracker, logger: LoggerMock(), contextStore: rig.contextStore,
            dateUtil: rig.dateUtil, notificationCenter: NotificationCenter(), dwellCoordinator: rig.dwell
        )
        let sync = GeofenceSyncCoordinatorMock()
        sync.refreshReturnValue = .success(())
        sync.handleMovementReturnValue = .success(())
        GeofenceMonitorBinder.bind(monitor: monitor, resolver: resolver, coordinator: sync, logger: LoggerMock(), dwellCoordinator: rig.dwell)
        return resolver
    }
}
