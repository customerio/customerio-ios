@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import CoreLocation
import Foundation
import SharedTests
import Testing

/// A Classic region callback carries its own `CLCircularRegion`, which may be a region a refresh
/// has since replaced under the same id. The wrapper compares it with the region the OS now
/// monitors and passes `.expired` when they differ; the binder then notes no ENTER, and the
/// resolver lets neither its ENTER nor its EXIT touch a visit. Driven through the real Classic
/// wrapper's delegate callbacks, the real binder, resolver, coordinator, storage, tracker and file
/// outbox. Only the OS's set of monitored regions is supplied (the wrapper's `monitoredRegion`
/// seam), with the clock, fixes and HTTP. Classic dates events by the real `Date()`; the scripted
/// wall clock stays behind it, so every callback reads as processed now. Internal chronology, not
/// physical callback acceptance.
@Suite("GeofenceStaleGenerationClassic", .serialized)
@MainActor
struct GeofenceStaleGenerationClassicTests {
    private static let circle = ClassicGenerationRig.circle
    private static let polygon = ClassicGenerationRig.polygon

    /// The wrapper's classification of a delivered region: a replaced one is `.expired`; the
    /// current one, the current one clamped to the cap, or one under an id the OS no longer
    /// monitors keep their own circle.
    @Test
    func deliveredRegion_expectClassifiedAgainstTheCurrentRegion() {
        let regions = RegionBox()
        let box = CircleBox()
        let monitor = CoreLocationGeofenceMonitor(
            logger: LoggerMock(), dateUtil: DateUtilStub(), readLocationAccess: { _ in GeofenceLocationAccess(delivery: .background, fullAccuracy: true) },
            monitoredRegion: { _, identifier in regions.current[identifier] }
        )
        monitor.setOnTransition { _, _, _, _, _, eventCircle, _ in box.delivered.append(eventCircle) }
        monitor.ownedRegionIdentifiers = ["circle", "unmonitored"]
        regions.current["circle"] = ClassicGenerationRig.region(radius: 200)

        monitor.locationManager(CLLocationManager(), didEnterRegion: ClassicGenerationRig.region(radius: 150))
        monitor.locationManager(CLLocationManager(), didExitRegion: ClassicGenerationRig.region(radius: 150))
        monitor.locationManager(CLLocationManager(), didEnterRegion: ClassicGenerationRig.region(radius: 200))
        regions.current["circle"] = ClassicGenerationRig.region(radius: 100)
        monitor.locationManager(CLLocationManager(), didEnterRegion: ClassicGenerationRig.region(radius: 100))
        monitor.locationManager(CLLocationManager(), didEnterRegion: ClassicGenerationRig.region(radius: 150, identifier: "unmonitored"))

        let delivered = box.delivered
        #expect(delivered.count == 5)
        guard delivered.count == 5,
              delivered[0] == .expired, delivered[1] == .expired,
              case .circle(let current) = delivered[2], case .circle(let clamped) = delivered[3],
              case .circle(let unmonitored) = delivered[4]
        else {
            Issue.record("expected circles, got \(delivered)")
            return
        }
        #expect(current.radius == 200)
        #expect(clamped.radius == 100)
        #expect(unmonitored.radius == 150)
    }

    /// A circle stay whose dwell went out (or was reserved). The replaced region's ENTER then EXIT
    /// arrive: both are delivered, and the stay keeps its id, flags and reservation. A fresh inside
    /// fix 600 s later queues no second DWELL; a reserved one is delivered once, as reserved.
    @Test(arguments: [false, true])
    func replacedRegionEnterAndExitOverAQualifiedCircleStay_expectKept(reserved: Bool) async throws {
        let rig = await ClassicGenerationRig()
        let stay = try await rig.qualifiedCircleStay(reserved: reserved)
        // A minute on, so the routed ENTER's evaluation takes a fresh fix, not an echo of the last.
        rig.advance(60)
        rig.callback(.enter, ClassicGenerationRig.region(radius: 150))
        await settleQuietly(0.4)
        rig.callback(.exit, ClassicGenerationRig.region(radius: 150))
        // The callback notes EXIT synchronously. Wait for routing and delivery to finish
        // before checking the stay.
        try #require(rig.dwell.pendingExitCallbacks[Self.circle.id]?.values.map(\.count) == [1])
        try #require(await settleOnMain(timeout: 30) { rig.dwell.pendingExitCallbacks.isEmpty })

        try await Self.expectKept(stay, in: rig, geofenceId: Self.circle.id, reserved: reserved)
        #expect(await rig.rows(.enter) == 1)
        #expect(await rig.rows(.exit) == 1)
        rig.advance(600)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)
        await rig.dwell.recordInsideEvidence(geofence: Self.circle, at: rig.clock.wall, source: "location_evidence")
        #expect(await rig.dwellRows().map(\.visitId) == [stay.visitId])
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// A polygon stay whose dwell went out (or was reserved). The replaced covering circle's ENTER
    /// arrives: the resolver still judges the current shape on a fresh fix (still inside), and the
    /// stay is kept. Its EXIT proves nothing about the shape. A fresh inside verdict 600 s later
    /// queues no second DWELL.
    @Test(arguments: [false, true])
    func replacedCoveringEnterAndExitOverAQualifiedPolygonStay_expectKept(reserved: Bool) async throws {
        let rig = await ClassicGenerationRig()
        let stay = try await rig.qualifiedPolygonStay(reserved: reserved)
        // A minute on, so the routed ENTER's evaluation takes a fresh fix, not an echo of the last.
        rig.advance(60)
        rig.callback(.enter, ClassicGenerationRig.region(latitude: 5.002, longitude: 6, radius: 300, identifier: Self.polygon.id))
        await settleQuietly(0.4)
        rig.callback(.exit, ClassicGenerationRig.region(latitude: 5.002, longitude: 6, radius: 300, identifier: Self.polygon.id))
        // As for the circle: noted in the callback, judged once its routing is done.
        try #require(rig.dwell.pendingExitCallbacks[Self.polygon.id]?.values.map(\.count) == [1])
        try #require(await settleOnMain(timeout: 30) { rig.dwell.pendingExitCallbacks.isEmpty })

        try await Self.expectKept(stay, in: rig, geofenceId: Self.polygon.id, reserved: reserved)
        rig.advance(600)
        await rig.pass()
        #expect(await rig.dwellRows().map(\.visitId) == [stay.visitId])
        rig.dwell.cancelEvidence(for: Self.polygon.id)
    }

    /// The stay is still stored with its id, entry timing and reservation. A reserved dwell may
    /// meanwhile have been delivered, as reserved, by the evidence a callback's wake re-arms; an
    /// emitted one is byte-for-byte unchanged.
    private static func expectKept(
        _ stay: GeofenceDwellVisit, in rig: ClassicGenerationRig, geofenceId: String, reserved: Bool
    ) async throws {
        let kept = try #require(await rig.storage.getDwellVisit(geofenceId: geofenceId))
        #expect(kept.visitId == stay.visitId)
        #expect(kept.timing == stay.timing)
        #expect(kept.dwellReservation == stay.dwellReservation)
        #expect(reserved || kept == stay)
    }

    /// Control: the CURRENT region's ENTER is a crossing as before: it ends the emitted stay, and
    /// the routed ENTER starts a new one.
    @Test
    func currentRegionEnterOverAnEmittedCircleStay_expectANewStay() async throws {
        let rig = await ClassicGenerationRig()
        let stay = try await rig.qualifiedCircleStay(reserved: false)
        rig.callback(.enter, ClassicGenerationRig.region(radius: 200))
        await settleQuietly(0.4)

        let current = try #require(await rig.storage.getDwellVisit(geofenceId: Self.circle.id))
        #expect(current.visitId != stay.visitId)
        #expect(!current.emitted)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// Control: the CURRENT region's EXIT ends the stay and is delivered.
    @Test
    func currentRegionExitOverAnEmittedCircleStay_expectEnded() async throws {
        let rig = await ClassicGenerationRig()
        _ = try await rig.qualifiedCircleStay(reserved: false)
        rig.callback(.exit, ClassicGenerationRig.region(radius: 200))
        // As in the stale tests: noted in the callback, judged once its routing is done.
        try #require(rig.dwell.pendingExitCallbacks[Self.circle.id]?.values.map(\.count) == [1])
        try #require(await settleOnMain(timeout: 30) { rig.dwell.pendingExitCallbacks.isEmpty })

        #expect(await rig.storage.getDwellVisit(geofenceId: Self.circle.id) == nil)
        #expect(await rig.rows(.exit) == 1)
    }
}

/// The event circles a handler was given. Unchecked: the wrapper calls its handler on the main actor.
final class CircleBox: @unchecked Sendable {
    var delivered: [GeofenceEventCircle] = []
}

/// The regions the OS monitors now, by id.
@MainActor
final class RegionBox {
    var current: [String: CLCircularRegion] = [:]
}

/// The Classic wrapper bound through the real binder to a real resolver, coordinator, storage,
/// tracker and file outbox, with a current circle (edited from 150 m to 200 m) and a current
/// polygon (its covering circle moved from (5.002, 6) to (5, 6)) registered with the OS.
@MainActor
final class ClassicGenerationRig {
    static let circle = Geofence(
        id: "circle", latitude: 1, longitude: 2, radius: 200, name: "circle",
        transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 2), dwellThresholdSeconds: 600
    )
    static let polygon = Geofence(
        id: "polygon", latitude: 5, longitude: 6, radius: 300, name: "polygon",
        transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 2),
        vertices: [
            LocationData(latitude: 4.9992, longitude: 5.9992),
            LocationData(latitude: 4.9992, longitude: 6.0008),
            LocationData(latitude: 5.0008, longitude: 6.0008),
            LocationData(latitude: 5.0008, longitude: 5.9992)
        ],
        dwellThresholdSeconds: 600
    )

    let storage: GeofenceStorage
    let outbox: PendingGeofenceMetricStore
    let contextStore: BackgroundDeliveryContextStore
    let clock = ManualGeofenceClock(wall: Date(timeIntervalSince1970: 1789215000))
    let dateUtil = DateUtilStub()
    let regions = RegionBox()
    private(set) var dwell: GeofenceDwellCoordinator!
    private(set) var resolver: PolygonMembershipResolver!
    private(set) var monitor: CoreLocationGeofenceMonitor!
    private let sync = GeofenceSyncCoordinatorMock()

    init() async {
        dateUtil.givenNow = clock.wall
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        self.storage = GeofenceStorage(directoryURL: directory, dateUtil: dateUtil)
        self.outbox = PendingGeofenceMetricStore(logger: LoggerMock(), directoryURL: directory.appendingPathComponent("outbox"))
        self.contextStore = BackgroundDeliveryContextStore(
            fileManager: .default, directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        contextStore.setUserId("user-1")
        contextStore.setCdpApiKey("test-key")
        await storage.setCachedGeofences([Self.circle, Self.polygon])
        await storage.recordRegistration(center: LocationData(latitude: 1, longitude: 2), businessIds: [Self.circle.id, Self.polygon.id])
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.failure(.transport)) }
        let tracker = GeofenceEventTracker(
            storage: storage, pendingStore: outbox, deliveryTracker: delivery, contextStore: contextStore,
            eventBusHandler: EventBusHandlerMock(), dateUtil: dateUtil, logger: LoggerMock()
        )
        let clock = clock
        self.dwell = GeofenceDwellCoordinator(
            storage: storage, transitionEmitter: tracker, contextStore: contextStore, logger: LoggerMock(),
            notificationCenter: NotificationCenter(),
            freshFixProvider: { Self.fix(latitude: 1, longitude: 2, at: clock.wall) },
            evidenceRetryDelay: 3600, clock: clock
        )
        let fixResolver = MovementFixResolver(logger: LoggerMock(), dateUtil: dateUtil)
        fixResolver.systemCachedFix = { nil }
        fixResolver.requestFreshFix = { [weak fixResolver] in
            fixResolver?.handleResolvedFix(Self.fix(latitude: 5, longitude: 6, at: clock.wall))
        }
        self.resolver = PolygonMembershipResolver(
            storage: storage, transitionEmitter: tracker, logger: LoggerMock(), contextStore: contextStore,
            dateUtil: dateUtil, fixResolver: fixResolver, notificationCenter: NotificationCenter(), dwellCoordinator: dwell
        )
        let regions = regions
        self.monitor = CoreLocationGeofenceMonitor(
            logger: LoggerMock(), dateUtil: dateUtil,
            readLocationAccess: { _ in GeofenceLocationAccess(delivery: .background, fullAccuracy: true) },
            monitoredRegion: { _, identifier in regions.current[identifier] }
        )
        monitor.ownedRegionIdentifiers = [Self.circle.id, Self.polygon.id]
        regions.current[Self.circle.id] = Self.region(radius: 200)
        regions.current[Self.polygon.id] = Self.region(latitude: 5, longitude: 6, radius: 300, identifier: Self.polygon.id)
        sync.refreshReturnValue = .success(())
        sync.handleMovementReturnValue = .success(())
        GeofenceMonitorBinder.bind(monitor: monitor, resolver: resolver, coordinator: sync, logger: LoggerMock(), dwellCoordinator: dwell)
    }

    static func region(latitude: Double = 1, longitude: Double = 2, radius: Double, identifier: String = "circle") -> CLCircularRegion {
        CLCircularRegion(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), radius: radius, identifier: identifier)
    }

    static func fix(latitude: Double, longitude: Double, at date: Date) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: date
        )
    }

    /// The OS delivers `region`'s event to the wrapper's delegate.
    func callback(_ transition: GeofenceTransition, _ region: CLCircularRegion) {
        if transition == .enter {
            monitor.locationManager(CLLocationManager(), didEnterRegion: region)
        } else {
            monitor.locationManager(CLLocationManager(), didExitRegion: region)
        }
    }

    func advance(_ seconds: TimeInterval) {
        clock.advance(seconds)
        dateUtil.givenNow = clock.wall
    }

    func pass() async {
        await resolver.evaluateMembership(geofenceIds: [Self.polygon.id], reason: .movement, requiresFreshFix: true)
    }

    /// A circle stay entered now, then emitted by a fresh fix 600 s later, or reserved and queued
    /// no further.
    func qualifiedCircleStay(reserved: Bool) async throws -> GeofenceDwellVisit {
        await dwell.handleBoundary(geofence: Self.circle, transition: .enter, occurredAt: clock.wall)
        dwell.cancelEvidence(for: Self.circle.id)
        advance(600)
        return try await qualify(Self.circle, reserved: reserved) { await self.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id) }
    }

    /// A polygon stay proven by a resolver pass now, then emitted by a pass 600 s later, or reserved.
    func qualifiedPolygonStay(reserved: Bool) async throws -> GeofenceDwellVisit {
        await pass()
        dwell.cancelEvidence(for: Self.polygon.id)
        advance(600)
        return try await qualify(Self.polygon, reserved: reserved) { await self.pass() }
    }

    private func qualify(_ geofence: Geofence, reserved: Bool, emit: () async -> Void) async throws -> GeofenceDwellVisit {
        let stay = try #require(await storage.getDwellVisit(geofenceId: geofence.id))
        if reserved {
            let reservation = GeofenceDwellReservation(
                occurredAtEpochMilliseconds: Int64((clock.wall.timeIntervalSince1970 * 1000).rounded()),
                enteredAtEpochMilliseconds: nil, durationSeconds: nil, thresholdSeconds: 600, detectionSource: "location_evidence"
            )
            guard case .reserved = await storage.reserveDwellEmission(reservation, for: stay, geofenceId: geofence.id) else {
                throw RigError.notReserved
            }
        } else {
            await emit()
        }
        dwell.cancelEvidence(for: geofence.id)
        let qualified = try #require(await storage.getDwellVisit(geofenceId: geofence.id))
        try #require(qualified.emitted != reserved)
        return qualified
    }

    func rows(_ transition: GeofenceTransition) async -> Int {
        await outbox.rows().filter { $0.transition == transition }.count
    }

    func dwellRows() async -> [PendingGeofenceMetric] {
        await outbox.rows().filter { $0.transition == .dwell }
    }

    enum RigError: Error { case notReserved }
}
