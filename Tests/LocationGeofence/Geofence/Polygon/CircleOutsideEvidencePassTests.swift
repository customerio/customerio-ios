@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import CoreLocation
import Foundation
import SharedTests
import Testing

/// A resolver pass already holds a fresh fix. When that fix is wholly outside a circle fence, the
/// SDK has seen the device away from it, whether or not Core Location raised an EXIT: the circle's
/// visit cannot continue into a dwell across that absence. Driven through the production pass,
/// coordinator, tracker and outbox; only the fix and the delivery transport are scripted.
@Suite("Circle outside evidence from resolver passes", .serialized)
@MainActor
struct CircleOutsideEvidencePassTests {
    /// The circle at the origin; 0.01° of latitude is about 1.1 km.
    private static let circle = Geofence(
        id: "circle", latitude: 0, longitude: 0, radius: 100, name: "circle",
        transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1),
        dwellThresholdSeconds: 60
    )
    /// Far from the circle: it only makes the pass run, as a registered polygon does.
    private static let polygon = Geofence(
        id: "polygon", latitude: 1, longitude: 1, radius: 300, name: "polygon",
        transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1),
        vertices: [
            LocationData(latitude: 0.9984, longitude: 0.9984),
            LocationData(latitude: 0.9984, longitude: 1.0016),
            LocationData(latitude: 1.0016, longitude: 1.0016),
            LocationData(latitude: 1.0016, longitude: 0.9984)
        ]
    )

    /// A movement pass's fresh fix wholly outside the circle ends its visit, so the device's
    /// return cannot qualify a dwell across the excursion. No EXIT is made up for it.
    @Test
    func movementPassFixWhollyOutsideTheCircleEndsItsVisit() async throws {
        let setup = await makeSetup()
        await setup.enterCircle()
        let visit = try #require(await setup.storage.getDwellVisit(geofenceId: Self.circle.id))
        setup.advance(30)

        setup.deliverFix(latitude: 0.01, accuracy: 10)
        await setup.resolver.evaluateAllPolygons(reason: .movement, requiresFreshFix: true)

        #expect(await setup.storage.getDwellVisit(geofenceId: Self.circle.id) == nil)
        setup.advance(60)
        await setup.coordinator.recordInsideEvidence(
            geofence: Self.circle, at: setup.clock.wall, source: "location_evidence"
        )
        let rows = await setup.outbox.rows()
        #expect(rows.filter { $0.transition == .dwell }.isEmpty)
        #expect(rows.filter { $0.transition == .exit }.isEmpty)
        #expect(await setup.storage.getDwellVisit(geofenceId: Self.circle.id)?.visitId != visit.visitId)
    }

    /// An accuracy circle that still reaches inside the fence decides nothing: the visit stays
    /// and later qualifies.
    @Test
    func passFixWhoseAccuracyReachesInsideTheCircleKeepsItsVisit() async throws {
        let setup = await makeSetup()
        await setup.enterCircle()
        let visit = try #require(await setup.storage.getDwellVisit(geofenceId: Self.circle.id))
        setup.advance(30)

        // About 150 m from the centre of a 100 m circle, give or take 80 m.
        setup.deliverFix(latitude: 0.00135, accuracy: 80)
        await setup.resolver.evaluateAllPolygons(reason: .movement, requiresFreshFix: true)

        #expect(await setup.storage.getDwellVisit(geofenceId: Self.circle.id)?.visitId == visit.visitId)
        setup.advance(60)
        await setup.coordinator.recordInsideEvidence(
            geofence: Self.circle, at: setup.clock.wall, source: "location_evidence"
        )
        #expect(await setup.outbox.rows().filter { $0.transition == .dwell }.map(\.visitId) == [visit.visitId])
    }

    /// A held fix taken before the visit began says nothing about it.
    @Test
    func heldFixOlderThanTheVisitKeepsIt() async throws {
        let setup = await makeSetup()
        let heldFix = ResolvedFix(
            latitude: 0.01, longitude: 0, horizontalAccuracy: 10, timestamp: setup.clock.wall
        )
        setup.advance(10)
        await setup.enterCircle()
        let visit = try #require(await setup.storage.getDwellVisit(geofenceId: Self.circle.id))

        await setup.resolver.evaluateAllPolygons(reason: .movement, heldFix: heldFix)

        #expect(await setup.storage.getDwellVisit(geofenceId: Self.circle.id)?.visitId == visit.visitId)
    }

    /// Approximate location blurs the fix by design: it proves nothing about leaving a circle.
    @Test
    func outsideFixUnderApproximateLocationKeepsTheVisit() async throws {
        let setup = await makeSetup(access: GeofenceLocationAccess(delivery: .background, fullAccuracy: false))
        await setup.enterCircle()
        let visit = try #require(await setup.storage.getDwellVisit(geofenceId: Self.circle.id))
        setup.advance(30)

        setup.deliverFix(latitude: 0.01, accuracy: 10)
        await setup.resolver.evaluateAllPolygons(reason: .movement, requiresFreshFix: true)

        #expect(await setup.storage.getDwellVisit(geofenceId: Self.circle.id)?.visitId == visit.visitId)
    }

    // MARK: - Setup

    @MainActor
    private final class Setup {
        let storage: GeofenceStorage
        let outbox: PendingGeofenceMetricStore
        let coordinator: GeofenceDwellCoordinator
        let resolver: PolygonMembershipResolver
        let clock: ManualGeofenceClock
        let dateUtil: DateUtilStub
        let fixResolver: MovementFixResolver
        var nextFix: CLLocation?

        init(
            storage: GeofenceStorage,
            outbox: PendingGeofenceMetricStore,
            coordinator: GeofenceDwellCoordinator,
            resolver: PolygonMembershipResolver,
            clock: ManualGeofenceClock,
            dateUtil: DateUtilStub,
            fixResolver: MovementFixResolver
        ) {
            self.storage = storage
            self.outbox = outbox
            self.coordinator = coordinator
            self.resolver = resolver
            self.clock = clock
            self.dateUtil = dateUtil
            self.fixResolver = fixResolver
        }

        /// Both clocks move together: the fix resolver judges freshness on `dateUtil`.
        func advance(_ seconds: TimeInterval) {
            clock.advance(seconds)
            dateUtil.givenNow = clock.wall
        }

        func enterCircle() async {
            await coordinator.handleBoundary(geofence: CircleOutsideEvidencePassTests.circle, transition: .enter, occurredAt: clock.wall)
        }

        /// The next fix request is answered with a fresh fix on the circle's meridian.
        func deliverFix(latitude: Double, accuracy: Double) {
            nextFix = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: 0),
                altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 10, timestamp: clock.wall
            )
        }
    }

    private func makeSetup(
        access: GeofenceLocationAccess = GeofenceLocationAccess(delivery: .background, fullAccuracy: true)
    ) async -> Setup {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = GeofenceStorage(fileManager: .default, directoryURL: directory)
        await storage.setCachedGeofences([Self.circle, Self.polygon])
        await storage.recordRegistration(
            center: LocationData(latitude: 0, longitude: 0), businessIds: [Self.circle.id, Self.polygon.id]
        )
        let contextStore = BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        contextStore.setUserId("user-1")
        let clock = ManualGeofenceClock(wall: Date())
        let dateUtil = DateUtilStub()
        dateUtil.givenNow = clock.wall
        let outbox = PendingGeofenceMetricStore(logger: LoggerMock(), directoryURL: directory.appendingPathComponent("outbox"))
        // Delivery fails, so every row the tracker persists stays in the outbox to be read.
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.failure(.transport)) }
        let tracker = GeofenceEventTracker(
            storage: storage, pendingStore: outbox, deliveryTracker: delivery, contextStore: contextStore,
            eventBusHandler: EventBusHandlerMock(), dateUtil: dateUtil, logger: LoggerMock()
        )
        let notificationCenter = NotificationCenter()
        let coordinator = GeofenceDwellCoordinator(
            storage: storage, transitionEmitter: tracker, contextStore: contextStore, logger: LoggerMock(),
            notificationCenter: notificationCenter, freshFixProvider: { nil }, clock: clock,
            locationAccess: { access }
        )
        let fixResolver = MovementFixResolver(logger: LoggerMock(), dateUtil: dateUtil)
        let setup = Setup(
            storage: storage, outbox: outbox, coordinator: coordinator,
            resolver: PolygonMembershipResolver(
                storage: storage, transitionEmitter: tracker, logger: LoggerMock(), contextStore: contextStore,
                dateUtil: dateUtil, fixResolver: fixResolver, notificationCenter: notificationCenter,
                dwellCoordinator: coordinator
            ),
            clock: clock, dateUtil: dateUtil, fixResolver: fixResolver
        )
        fixResolver.systemCachedFix = { nil }
        fixResolver.requestFreshFix = { [weak setup, weak fixResolver] in
            guard let fix = setup?.nextFix else { return fixResolver?.handleRequestFailure() ?? () }
            setup?.nextFix = nil
            fixResolver?.handleResolvedFix(fix)
        }
        return setup
    }
}
