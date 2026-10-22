@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import CoreLocation
import Foundation
import SharedTests
import Testing

/// A polygon visit's boundaries as location passes judge them: what an EXIT found by a fix may
/// report, and what a pass finds when the belief is already outside. Through the production
/// resolver, dwell coordinator, tracker and file outbox; only the clocks and the delivery transport
/// are scripted, and delivery fails so every row the tracker persists stays in the outbox.
@Suite("Polygon visit boundaries from location passes", .serialized)
@MainActor
struct PolygonVisitBoundaryTests {
    /// About 180 m square around (5, 6), inside a 300 m covering circle.
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

    /// A fix outside the polygon ends the visit: the EXIT is timed from the observed entry to the
    /// fix, and carries as its uncertainty the gap since the device was last proven inside — here
    /// the decisive entry fix itself.
    @Test
    func fixExitSoonAfterTheLastInsideProofReportsTheDuration() async throws {
        let setup = await makeSetup()
        await setup.judge(.outside)
        setup.advance(30)
        let enteredAt = setup.clock.wall
        await setup.judge(.inside)
        let visit = try #require(await setup.storage.getDwellVisit(geofenceId: Self.polygon.id))
        try #require(visit.entryObserved)
        setup.advance(90)

        await setup.judge(.outside)

        let rows = await setup.exitRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId == visit.visitId)
        #expect(rows[0].enteredAt.map { Int($0.timeIntervalSince1970) } == Int(enteredAt.timeIntervalSince1970))
        #expect(rows[0].visitDurationSeconds == 90)
        #expect(rows[0].visitDurationUncertaintySeconds == 90)
        #expect(rows[0].detectionSource == "location_evidence")
        #expect(await setup.storage.getDwellVisit(geofenceId: Self.polygon.id) == nil)
    }

    /// An outside fix long after the last inside proof still times the EXIT to the fix: the device
    /// left at some unknown point in the gap, which the uncertainty reports in full.
    @Test
    func fixExitLongAfterTheLastInsideProofReportsTheWholeGapAsUncertainty() async throws {
        let setup = await makeSetup()
        await setup.judge(.outside)
        setup.advance(30)
        await setup.judge(.inside)
        let visit = try #require(await setup.storage.getDwellVisit(geofenceId: Self.polygon.id))
        try #require(visit.entryObserved)
        setup.advance(GeofenceConstants.polygonOutsideProofMaxAge + 3600)

        await setup.judge(.outside)

        let rows = await setup.exitRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId == visit.visitId)
        #expect(rows[0].enteredAt.map { Int($0.timeIntervalSince1970) } == Int(visit.enteredAt.timeIntervalSince1970))
        #expect(rows[0].visitDurationSeconds == Int(GeofenceConstants.polygonOutsideProofMaxAge) + 3600)
        #expect(rows[0].visitDurationUncertaintySeconds == rows[0].visitDurationSeconds)
        #expect(rows[0].trackEventProperties["visitDurationUncertaintySeconds"] as? Int == rows[0].visitDurationSeconds)
        #expect(await setup.storage.getDwellVisit(geofenceId: Self.polygon.id) == nil)
    }

    /// A visit discovered inside, with no observed entry, ends with an EXIT that names the visit
    /// and nothing else: no entry, no duration, no uncertainty.
    @Test
    func fixExitOfADiscoveredVisitCarriesOnlyTheVisitId() async throws {
        let setup = await makeSetup()
        await setup.judge(.inside)
        let visit = try #require(await setup.storage.getDwellVisit(geofenceId: Self.polygon.id))
        try #require(!visit.entryObserved)
        setup.advance(90)

        await setup.judge(.outside)

        let rows = await setup.exitRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId == visit.visitId)
        #expect(rows[0].enteredAt == nil)
        #expect(rows[0].visitDurationSeconds == nil)
        #expect(rows[0].visitDurationUncertaintySeconds == nil)
        #expect(rows[0].trackEventProperties["visitDurationUncertaintySeconds"] == nil)
    }

    /// The covering circle's EXIT ends the polygon visit too: the EXIT names the visit, is timed
    /// to the circle crossing, and reports the gap since the last decisive inside proof.
    @Test
    func coveringCircleExitCarriesTheVisitAndItsUncertainty() async throws {
        let setup = await makeSetup()
        await setup.judge(.outside)
        setup.advance(30)
        await setup.judge(.inside)
        let visit = try #require(await setup.storage.getDwellVisit(geofenceId: Self.polygon.id))
        setup.advance(200)

        await setup.resolver.applyCoveringCircleExit(geofence: Self.polygon, eventCircle: .unknown, occurredAt: setup.clock.wall)

        let rows = await setup.exitRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId == visit.visitId)
        #expect(rows[0].visitDurationSeconds == 200)
        #expect(rows[0].visitDurationUncertaintySeconds == 200)
        #expect(rows[0].detectionSource == "covering_circle")
        #expect(await setup.storage.getDwellVisit(geofenceId: Self.polygon.id) == nil)
    }

    /// A marginal arrival — a corroborated fix whose accuracy disk crossed the edge — begins the
    /// visit but is no proof of the stay: the EXIT is timed from it, and with nothing decisive
    /// since, the uncertainty is the whole stay.
    @Test
    func fixExitAfterOnlyAMarginalArrivalReportsTheWholeStayAsUncertainty() async throws {
        let setup = await makeSetup()
        await setup.judge(.outside)
        setup.advance(30)
        await setup.judge(.inside, qualifiesDwell: false)
        try #require(await setup.storage.getDwellVisit(geofenceId: Self.polygon.id)?.entryObserved == true)
        setup.advance(60)

        await setup.judge(.outside)

        let rows = await setup.exitRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitDurationSeconds == 60)
        #expect(rows[0].visitDurationUncertaintySeconds == 60)
    }

    /// The same stay, decisively confirmed inside before it is left, is timed from its entry with
    /// the uncertainty counted from that confirmation.
    @Test
    func decisiveConfirmationAfterAMarginalArrivalTimesTheExit() async throws {
        let setup = await makeSetup()
        await setup.judge(.outside)
        setup.advance(30)
        await setup.judge(.inside, qualifiesDwell: false)
        setup.advance(30)
        await setup.judge(.inside)
        setup.advance(30)

        await setup.judge(.outside)

        let rows = await setup.exitRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitDurationSeconds == 60)
        #expect(rows[0].visitDurationUncertaintySeconds == 30)
    }

    /// An outside confirmation that was suspended while a newer inside pass began a stay must not
    /// end that stay: only a visit begun before the outside fix, while the belief is still
    /// outside, is the one left behind.
    @Test
    func outsideConfirmationLeavesAVisitBegunAfterItsFix() async throws {
        let setup = await makeSetup()
        await setup.judge(.outside)
        let outsideAt = setup.clock.wall
        setup.advance(30)
        await setup.judge(.inside)
        let newer = try #require(await setup.storage.getDwellVisit(geofenceId: Self.polygon.id))

        await setup.coordinator.endVisitLeftOutside(geofence: Self.polygon, outsideAt: outsideAt, expectedUserId: "user-1")

        #expect(await setup.storage.getDwellVisit(geofenceId: Self.polygon.id)?.visitId == newer.visitId)
        // Nor one begun before it while the belief has since turned inside.
        let later = GeofenceExitMark(
            date: setup.clock.wall.addingTimeInterval(1), processedAt: setup.clock.read(), source: .outsideEvidence
        )
        #expect(await setup.storage.removeDwellVisitLeftOutside(geofenceId: Self.polygon.id, endedBy: later) == nil)
        #expect(await setup.storage.getDwellVisit(geofenceId: Self.polygon.id)?.visitId == newer.visitId)
    }

    /// The wall clock stepped back behind the stranded visit's entry while the process stayed
    /// alive. Dates no longer order the two, so the outside confirmation is placed by processing:
    /// it ran after the visit was recorded, and the visit is ended all the same.
    @Test
    func outsideConfirmationAfterABackwardClockStepEndsTheStrandedVisit() async throws {
        let setup = await makeSetup()
        await setup.judge(.outside)
        setup.advance(30)
        await setup.judge(.inside)
        let stranded = try #require(await setup.storage.getDwellVisit(geofenceId: Self.polygon.id))
        setup.advance(60)
        setup.stepWall(-3600)
        // The EXIT's membership write, whose visit removal was lost; dated on the stepped clock.
        let write = await setup.storage.recordPolygonMembership(
            .outside, forIdentifier: Self.polygon.id, now: setup.clock.wall
        )
        try #require(write == .deliver(.exit))
        try #require(await setup.storage.getDwellVisit(geofenceId: Self.polygon.id)?.visitId == stranded.visitId)
        setup.advance(60)

        await setup.judge(.outside)

        #expect(await setup.storage.getDwellVisit(geofenceId: Self.polygon.id) == nil)
        #expect(await setup.exitRows().isEmpty)
    }

    /// A confirmation keeps the inside proof fresh: a stay confirmed inside an hour in and left
    /// a minute later is timed over the whole hour.
    @Test
    func confirmedInsideKeepsALaterFixExitTimed() async throws {
        let setup = await makeSetup()
        await setup.judge(.outside)
        setup.advance(30)
        await setup.judge(.inside)
        setup.advance(3600)
        await setup.judge(.inside)
        setup.advance(60)

        await setup.judge(.outside)

        let rows = await setup.exitRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitDurationSeconds == 3660)
        #expect(rows[0].visitDurationUncertaintySeconds == 60)
    }

    /// The belief went outside but the visit's removal never ran — the process died between the
    /// two writes. The next pass confirms outside with nothing to deliver, and ends the visit it
    /// finds: no EXIT, no duration, and a later inside fix starts a stay of its own.
    @Test
    func confirmedOutsideWithAVisitLeftBehindEndsItWithoutAnExit() async throws {
        let setup = await makeSetup()
        await setup.judge(.outside)
        setup.advance(30)
        await setup.judge(.inside)
        let stranded = try #require(await setup.storage.getDwellVisit(geofenceId: Self.polygon.id))
        setup.advance(60)
        // The membership write of an EXIT whose visit removal was lost.
        let write = await setup.storage.recordPolygonMembership(
            .outside, forIdentifier: Self.polygon.id, onlyIfBeliefPredates: setup.clock.wall, now: setup.clock.wall
        )
        try #require(write == .deliver(.exit))
        try #require(await setup.storage.getDwellVisit(geofenceId: Self.polygon.id)?.visitId == stranded.visitId)
        setup.advance(60)

        await setup.judge(.outside)

        #expect(await setup.storage.getDwellVisit(geofenceId: Self.polygon.id) == nil)
        #expect(await setup.exitRows().isEmpty)

        setup.advance(3600)
        await setup.judge(.inside)
        let next = try #require(await setup.storage.getDwellVisit(geofenceId: Self.polygon.id))
        #expect(next.visitId != stranded.visitId)
        #expect(next.entryObserved == false)
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

        init(
            storage: GeofenceStorage,
            outbox: PendingGeofenceMetricStore,
            coordinator: GeofenceDwellCoordinator,
            resolver: PolygonMembershipResolver,
            clock: ManualGeofenceClock,
            dateUtil: DateUtilStub
        ) {
            self.storage = storage
            self.outbox = outbox
            self.coordinator = coordinator
            self.resolver = resolver
            self.clock = clock
            self.dateUtil = dateUtil
        }

        /// Both clocks move together: the tracker's cooldown and the fix resolver read `dateUtil`.
        func advance(_ seconds: TimeInterval) {
            clock.advance(seconds)
            dateUtil.givenNow = clock.wall
        }

        /// A time change: the wall clock moves, uptime does not.
        func stepWall(_ seconds: TimeInterval) {
            clock.stepWall(seconds)
            dateUtil.givenNow = clock.wall
        }

        /// A pass's verdict for the polygon, from a fix taken now: decisive unless `qualifiesDwell`
        /// is false, which is a marginal arrival committed on corroboration.
        func judge(_ membership: PolygonMembership, qualifiesDwell: Bool = true) async {
            await resolver.apply(
                membership, to: PolygonVisitBoundaryTests.polygon, evidence: clock.wall, confirmedByFix: true,
                evaluatedRing: PolygonVisitBoundaryTests.polygon.vertices, qualifiesDwell: qualifiesDwell
            )
        }

        func exitRows() async -> [PendingGeofenceMetric] {
            await outbox.rows().filter { $0.transition == .exit }.sorted { $0.timestamp < $1.timestamp }
        }
    }

    private func makeSetup() async -> Setup {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = GeofenceStorage(fileManager: .default, directoryURL: directory)
        await storage.setCachedGeofences([Self.polygon])
        await storage.recordRegistration(center: LocationData(latitude: 5, longitude: 6), businessIds: [Self.polygon.id])
        let contextStore = BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        contextStore.setUserId("user-1")
        // In the past, so the clock can advance hours without the storage clamping a fix to now.
        let clock = ManualGeofenceClock(wall: Date(timeIntervalSinceNow: -7 * 86400))
        let dateUtil = DateUtilStub()
        dateUtil.givenNow = clock.wall
        let outbox = PendingGeofenceMetricStore(logger: LoggerMock(), directoryURL: directory.appendingPathComponent("outbox"))
        let delivery = GeofenceDeliveryTrackerMock()
        delivery.trackMetricClosure = { _, _, onComplete in onComplete(.failure(.transport)) }
        let tracker = GeofenceEventTracker(
            storage: storage, pendingStore: outbox, deliveryTracker: delivery, contextStore: contextStore,
            eventBusHandler: EventBusHandlerMock(), dateUtil: dateUtil, logger: LoggerMock()
        )
        let notificationCenter = NotificationCenter()
        let access = GeofenceLocationAccess(delivery: .background, fullAccuracy: true)
        let coordinator = GeofenceDwellCoordinator(
            storage: storage, transitionEmitter: tracker, contextStore: contextStore, logger: LoggerMock(),
            notificationCenter: notificationCenter, freshFixProvider: { nil }, evidenceRetryDelay: 3600, clock: clock,
            locationAccess: { access }
        )
        let fixResolver = MovementFixResolver(logger: LoggerMock(), dateUtil: dateUtil)
        fixResolver.systemCachedFix = { nil }
        fixResolver.requestFreshFix = { [weak fixResolver] in fixResolver?.handleRequestFailure() }
        return Setup(
            storage: storage, outbox: outbox, coordinator: coordinator,
            resolver: PolygonMembershipResolver(
                storage: storage, transitionEmitter: tracker, logger: LoggerMock(), contextStore: contextStore,
                dateUtil: dateUtil, fixResolver: fixResolver, notificationCenter: notificationCenter,
                dwellCoordinator: coordinator
            ),
            clock: clock, dateUtil: dateUtil
        )
    }
}
