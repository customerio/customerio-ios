@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import CoreLocation
import Foundation
import SharedTests
import Testing

private let monitorAvailable: Bool = {
    if #available(iOS 17.0, *) { return true }
    return false
}()

/// An ENTER that is not a crossing — a `CLMonitor` correction of a state it assumed, or a baseline
/// heal — says the device is inside, not that it arrived again. It must not end a stay whose dwell
/// was already emitted or reserved, or that stay qualifies a second time. Driven through the real
/// `CLMonitor` wrapper (only CoreLocation is faked), the monitor binder, the polygon resolver, the
/// dwell coordinator and a real tracker's outbox; only the clock, the fixes and the transport are
/// scripted.
@Suite("GeofenceDwellCorrectionEnter", .serialized, .enabled(if: monitorAvailable))
@MainActor
struct GeofenceDwellCorrectionEnterTests {
    /// 150 m around (1, 2); 0.01° of latitude is about 1.1 km.
    private static let circle = Geofence(
        id: "circle", latitude: 1, longitude: 2, radius: 150, name: "circle",
        transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1),
        dwellThresholdSeconds: 600
    )
    /// About 180 m square around (5, 6), well inside its 300 m covering circle.
    private static let polygon = Geofence(
        id: "polygon", latitude: 5, longitude: 6, radius: 300, name: "polygon",
        transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1),
        vertices: [
            LocationData(latitude: 4.9992, longitude: 5.9992),
            LocationData(latitude: 4.9992, longitude: 6.0008),
            LocationData(latitude: 5.0008, longitude: 6.0008),
            LocationData(latitude: 5.0008, longitude: 5.9992)
        ],
        dwellThresholdSeconds: 600
    )

    /// The review's sequence: a circle registered with its state assumed outside, a stay proven
    /// and emitted, then an hour later a sync's baseline heal reads a fresh inside fix and
    /// synthesizes an ENTER. The device never left: the stay keeps its id, stays emitted, and the
    /// outbox holds one DWELL however long it goes on.
    @Test
    @available(iOS 17.0, *)
    func healEnterOnAnEmittedCircleVisitKeepsItsSingleDwell() async throws {
        let rig = await Rig.make()
        await rig.register(Self.circle, seenAt: nil)
        let emitted = try await rig.emitCircleDwell()

        rig.advance(3600)
        rig.authority.answerCachedLocation = { [rig] in rig.fix(at: Self.circle, latitudeOffset: 0) }
        rig.monitor.setMonitoredRegions([Rig.request(for: Self.circle)])
        await rig.awaitMonitorState(.enter, for: Self.circle.id)
        // The re-armed evidence and the routed ENTER have landed.
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)
        rig.advance(600)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        #expect(await rig.dwellRows().map(\.visitId) == [emitted.visitId])
        let stored = await rig.storage.getDwellVisit(geofenceId: Self.circle.id)
        #expect(stored?.visitId == emitted.visitId)
        #expect(stored?.emitted == true)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// The same for a polygon: `CLMonitor` corrects the covering circle it assumed outside, and the
    /// resolver's fresh fix finds the device still inside the shape. One DWELL, one visit.
    @Test
    @available(iOS 17.0, *)
    func correctionEnterOnAnEmittedPolygonVisitKeepsItsSingleDwell() async throws {
        let rig = await Rig.make()
        await rig.register(Self.polygon, seenAt: nil)
        await rig.resolver.evaluateMembership(geofenceIds: [Self.polygon.id], reason: .movement, requiresFreshFix: true)
        rig.advance(600)
        await rig.resolver.evaluateMembership(geofenceIds: [Self.polygon.id], reason: .movement, requiresFreshFix: true)
        let emitted = try #require(await rig.storage.getDwellVisit(geofenceId: Self.polygon.id))
        try #require(emitted.emitted)
        try #require(await rig.dwellRows().count == 1)

        rig.advance(3600)
        rig.os.deliver(identifier: Self.polygon.id, state: .satisfied, at: rig.clock.wall)
        await rig.awaitMonitorState(.enter, for: Self.polygon.id)
        rig.advance(600)
        await rig.resolver.evaluateMembership(geofenceIds: [Self.polygon.id], reason: .movement, requiresFreshFix: true)

        #expect(await rig.dwellRows().map(\.visitId) == [emitted.visitId])
        let stored = await rig.storage.getDwellVisit(geofenceId: Self.polygon.id)
        #expect(stored?.visitId == emitted.visitId)
        #expect(stored?.emitted == true)
        rig.dwell.cancelEvidence(for: Self.polygon.id)
    }

    /// A dwell reserved but not yet queued — its outbox write failed, or the process died first —
    /// is a fact about the stay. A correction ENTER leaves it, and it is delivered as reserved:
    /// its visit id, timestamp and entry.
    @Test
    @available(iOS 17.0, *)
    func correctionEnterLeavesAReservedDwellToBeDeliveredAsReserved() async throws {
        let rig = await Rig.make()
        await rig.register(Self.circle, seenAt: nil)
        let enteredAt = rig.clock.wall
        let reservation = GeofenceDwellReservation(
            occurredAtEpochMilliseconds: Int64(enteredAt.timeIntervalSince1970 * 1000) + 600000,
            enteredAtEpochMilliseconds: Int64(enteredAt.timeIntervalSince1970 * 1000), durationSeconds: 600,
            thresholdSeconds: 600, detectionSource: "location_evidence"
        )
        let reserved = GeofenceDwellVisit(
            visitId: UUID().uuidString, enteredAt: enteredAt, geometryRevision: Self.circle.dwellRevision,
            userId: "user-1", emitted: false, entryObserved: true, dwellReservation: reservation,
            timing: GeofenceVisitTiming(enteredAt: enteredAt, recordedAt: rig.clock.read())
        )
        try #require(await rig.storage.saveDwellVisit(reserved, geofenceId: Self.circle.id))

        rig.advance(3600)
        rig.os.deliver(identifier: Self.circle.id, state: .satisfied, at: rig.clock.wall)
        await rig.awaitMonitorState(.enter, for: Self.circle.id)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        let rows = await rig.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId == reserved.visitId)
        #expect(Int64((rows[0].timestamp.timeIntervalSince1970 * 1000).rounded()) == reservation.occurredAtEpochMilliseconds)
        #expect(rows[0].enteredAt == enteredAt)
        #expect(rows[0].dwellDurationSeconds == 600)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// Control: an ENTER `CLMonitor` raises on leaving a state it observed is a real crossing. The
    /// old stay, whose EXIT never reached the SDK, ends; the new one gets its own id and qualifies
    /// with its own entry.
    @Test
    @available(iOS 17.0, *)
    func crossingEnterAfterAnEmittedVisitStartsANewStayThatQualifies() async throws {
        let rig = await Rig.make()
        await rig.register(Self.circle, seenAt: rig.fix(at: Self.circle, latitudeOffset: 0.01))
        let emitted = try await rig.emitCircleDwell()

        rig.advance(3600)
        let crossedAt = rig.clock.wall
        rig.os.deliver(identifier: Self.circle.id, state: .satisfied, at: crossedAt)
        await rig.awaitMonitorState(.enter, for: Self.circle.id)
        await settleQuietly(0.3)

        let replaced = try #require(await rig.storage.getDwellVisit(geofenceId: Self.circle.id))
        #expect(replaced.visitId != emitted.visitId)
        #expect(replaced.emitted == false)
        rig.advance(600)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        let rows = await rig.dwellRows()
        try #require(rows.count == 2)
        #expect(rows[0].visitId == emitted.visitId)
        #expect(rows[1].visitId == replaced.visitId)
        #expect(rows[1].enteredAt == crossedAt)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// Control: a stay not yet qualified when the correction arrives restarts there. Its time
    /// before the correction counts for nothing — the OS assumed the device outside, and nothing
    /// watched it return — so the re-armed evidence, due by the old stay's clock, emits nothing.
    @Test
    @available(iOS 17.0, *)
    func correctionEnterRestartsAnUnqualifiedStayWithNoEarlyDwell() async throws {
        let rig = await Rig.make()
        await rig.register(Self.circle, seenAt: nil)
        await rig.dwell.handleBoundary(geofence: Self.circle, transition: .enter, occurredAt: rig.clock.wall)
        let unqualified = try #require(await rig.storage.getDwellVisit(geofenceId: Self.circle.id))
        rig.dwell.cancelEvidence(for: Self.circle.id)

        rig.advance(600)
        rig.os.deliver(identifier: Self.circle.id, state: .satisfied, at: rig.clock.wall)
        await rig.awaitMonitorState(.enter, for: Self.circle.id)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        #expect(await rig.dwellRows().isEmpty)
        let restarted = try #require(await rig.storage.getDwellVisit(geofenceId: Self.circle.id))
        #expect(restarted.visitId != unqualified.visitId)
        rig.advance(600)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        let rows = await rig.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId == restarted.visitId)
        #expect(rows[0].enteredAt == nil)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// A crossing ENTER on a polygon's covering circle, then a correction, both delivered before
    /// either's routing task runs. The crossing means the device left and came back, so the emitted
    /// stay ends, though the resolver, which missed the exit, still finds the device inside: the
    /// routed ENTER reaches the coordinator only as inside evidence. The correction noted after
    /// it must not hide that. `CLMonitor`'s serial consumer cannot interleave them like this, so
    /// the binder is driven directly, with the flag each producer passes: true from a classic
    /// region event, false from a heal.
    @Test
    @available(iOS 17.0, *)
    func correctionBehindAPendingCrossingStillEndsTheEmittedStay() async throws {
        let rig = await Rig.make()
        await rig.resolver.evaluateMembership(geofenceIds: [Self.polygon.id], reason: .movement, requiresFreshFix: true)
        rig.advance(600)
        await rig.resolver.evaluateMembership(geofenceIds: [Self.polygon.id], reason: .movement, requiresFreshFix: true)
        let emitted = try #require(await rig.storage.getDwellVisit(geofenceId: Self.polygon.id))
        try #require(emitted.emitted)
        let monitor = MockGeofenceRegionMonitor()
        rig.bind(monitor)

        rig.advance(3600)
        monitor.simulateTransition(identifier: Self.polygon.id, transition: .enter, location: nil, occurredAt: rig.clock.wall)
        rig.advance(5)
        monitor.simulateTransition(
            identifier: Self.polygon.id, transition: .enter, location: nil, occurredAt: rig.clock.wall, entryObserved: false
        )
        await settleQuietly(0.5)

        let current = try #require(await rig.storage.getDwellVisit(geofenceId: Self.polygon.id))
        #expect(current.visitId != emitted.visitId)
        rig.advance(600)
        await rig.resolver.evaluateMembership(geofenceIds: [Self.polygon.id], reason: .movement, requiresFreshFix: true)

        let rows = await rig.dwellRows()
        try #require(rows.count == 2)
        #expect(rows[0].visitId == emitted.visitId)
        #expect(rows[1].visitId == current.visitId)
        rig.dwell.cancelEvidence(for: Self.polygon.id)
    }

    // MARK: - Rig

    @available(iOS 17.0, *)
    @MainActor
    final class Rig {
        let storage: GeofenceStorage
        let outbox: PendingGeofenceMetricStore
        let tracker: GeofenceEventTracker
        let contextStore: BackgroundDeliveryContextStore
        let clock = ManualGeofenceClock(wall: Date(timeIntervalSince1970: 1789215000))
        let dateUtil = DateUtilStub()
        let os = FakeConditionMonitor()
        let authority = FakeLocationAuthority()
        let defaultsSuite = "io.customer.test.geofence.\(UUID().uuidString)"
        private(set) var dwell: GeofenceDwellCoordinator!
        private(set) var resolver: PolygonMembershipResolver!
        private(set) var monitor: CLMonitorGeofenceMonitor!
        private let sync = GeofenceSyncCoordinatorMock()

        private init() {
            dateUtil.givenNow = clock.wall
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            self.storage = GeofenceStorage(directoryURL: directory, dateUtil: dateUtil)
            self.outbox = PendingGeofenceMetricStore(logger: LoggerMock(), directoryURL: directory.appendingPathComponent("outbox"))
            self.contextStore = BackgroundDeliveryContextStore(
                fileManager: .default,
                directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            )
            contextStore.setUserId("user-1")
            // A key, so a flush sends rows over HTTP, which fails: every row stays in the outbox to
            // be read. Without one, a flush hands rows to the event bus and drops them.
            contextStore.setCdpApiKey("test-key")
            let delivery = GeofenceDeliveryTrackerMock()
            delivery.trackMetricClosure = { _, _, onComplete in onComplete(.failure(.transport)) }
            self.tracker = GeofenceEventTracker(
                storage: storage, pendingStore: outbox, deliveryTracker: delivery, contextStore: contextStore,
                eventBusHandler: EventBusHandlerMock(), dateUtil: dateUtil, logger: LoggerMock()
            )
            sync.refreshReturnValue = .success(())
            sync.handleMovementReturnValue = .success(())
        }

        /// The device sits at each fence's centre throughout: every fresh fix asked for is there.
        static func make() async -> Rig {
            let rig = Rig()
            await rig.storage.setCachedGeofences([GeofenceDwellCorrectionEnterTests.circle, GeofenceDwellCorrectionEnterTests.polygon])
            await rig.storage.recordRegistration(
                center: LocationData(latitude: 1, longitude: 2),
                businessIds: [GeofenceDwellCorrectionEnterTests.circle.id, GeofenceDwellCorrectionEnterTests.polygon.id]
            )
            rig.dwell = GeofenceDwellCoordinator(
                storage: rig.storage, transitionEmitter: rig.tracker, contextStore: rig.contextStore, logger: LoggerMock(),
                notificationCenter: NotificationCenter(),
                freshFixProvider: { [weak rig] in rig?.fix(at: GeofenceDwellCorrectionEnterTests.circle, latitudeOffset: 0) },
                // Retries never fire within a test; each test asks for evidence itself.
                evidenceRetryDelay: 3600,
                clock: rig.clock
            )
            let fixResolver = MovementFixResolver(logger: LoggerMock(), dateUtil: rig.dateUtil)
            fixResolver.systemCachedFix = { nil }
            fixResolver.requestFreshFix = { [weak rig, weak fixResolver] in
                guard let fix = rig?.fix(at: GeofenceDwellCorrectionEnterTests.polygon, latitudeOffset: 0) else { return }
                fixResolver?.handleResolvedFix(fix)
            }
            rig.resolver = PolygonMembershipResolver(
                storage: rig.storage, transitionEmitter: rig.tracker, logger: LoggerMock(), contextStore: rig.contextStore,
                dateUtil: rig.dateUtil, fixResolver: fixResolver, notificationCenter: NotificationCenter(),
                dwellCoordinator: rig.dwell
            )
            let os = rig.os
            rig.monitor = CLMonitorGeofenceMonitor(
                logger: LoggerMock(), storage: rig.storage,
                userDefaults: UserDefaults(suiteName: rig.defaultsSuite) ?? .standard,
                dateUtil: rig.dateUtil, authority: rig.authority, makeConditionMonitor: { _ in os }
            )
            rig.bind(rig.monitor)
            _ = await settleOnMain { os.hasSubscriber }
            return rig
        }

        func bind(_ monitor: GeofenceRegionMonitoring) {
            GeofenceMonitorBinder.bind(
                monitor: monitor, resolver: resolver, coordinator: sync, logger: LoggerMock(), dwellCoordinator: dwell
            )
        }

        static func request(for geofence: Geofence) -> GeofenceRegionRequest {
            GeofenceRegionRequest(
                identifier: geofence.id, center: LocationData(latitude: geofence.latitude, longitude: geofence.longitude),
                radius: geofence.radius, transitionTypes: [.enter, .exit]
            )
        }

        /// Registers `geofence`'s circle with `CLMonitor`. With no fix the state is assumed outside,
        /// and the ENTER the OS answers it with is a correction, not a crossing; with `seenAt`
        /// outside, the state is observed, and the next ENTER is a crossing.
        func register(_ geofence: Geofence, seenAt fix: CLLocation?) async {
            authority.answerCachedLocation = { fix }
            monitor.setMonitoredRegions([Self.request(for: geofence)])
            _ = await settleOnMain { self.os.held[geofence.id] != nil }
            await awaitMonitorState(.exit, for: geofence.id)
            authority.answerCachedLocation = nil
        }

        /// A circle stay entered now, qualified by a fresh fix after its threshold.
        func emitCircleDwell() async throws -> GeofenceDwellVisit {
            let circle = GeofenceDwellCorrectionEnterTests.circle
            await dwell.handleBoundary(geofence: circle, transition: .enter, occurredAt: clock.wall)
            advance(600)
            await dwell.requestQualifyingEvidence(geofenceId: circle.id)
            let visit = try #require(await storage.getDwellVisit(geofenceId: circle.id))
            try #require(visit.emitted)
            try #require(await dwellRows().map(\.visitId) == [visit.visitId])
            return visit
        }

        /// Waits for the monitor's stored state, then for the binder's routing task to land.
        func awaitMonitorState(_ state: GeofenceTransition, for identifier: String) async {
            for _ in 0 ..< 200 where await storage.getMonitorRegionRecords()[identifier]?.lastState != state {
                try? await Task.sleep(nanoseconds: 10000000)
            }
            await settleQuietly(0.3)
        }

        func advance(_ seconds: TimeInterval) {
            clock.advance(seconds)
            dateUtil.givenNow = clock.wall
        }

        /// A 10 m fix taken now, `latitudeOffset` degrees north of `geofence`'s centre.
        func fix(at geofence: Geofence, latitudeOffset: Double) -> CLLocation {
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: geofence.latitude + latitudeOffset, longitude: geofence.longitude),
                altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: clock.wall
            )
        }

        func dwellRows() async -> [PendingGeofenceMetric] {
            await outbox.rows().filter { $0.transition == .dwell }
        }
    }
}
