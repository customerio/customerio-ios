@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import CoreLocation
import Foundation
import SharedTests
import Testing

/// A completed visit's duration on an EXIT-only circle with dwell disabled, end to end: Core
/// Location boundaries through the production resolver, the dwell coordinator, the tracker and the
/// file outbox. Only the clocks and the delivery transport are scripted; delivery fails, so every
/// row the tracker persists stays in the outbox to be read.
@Suite("EXIT duration against outside evidence, through the outbox", .serialized)
@MainActor
struct ExitDurationOutsideEvidenceOutboxTests {
    /// EXIT-only, threshold 0: no ENTER or DWELL is ever delivered, but its visits are timed.
    private static let circle = Geofence(
        id: "circle", latitude: 0, longitude: 0, radius: 100, name: "circle",
        transitionTypes: [.exit], lastUpdated: Date(timeIntervalSince1970: 1)
    )

    /// A circle-only pass holds a fresh fix wholly outside the circle mid-visit: the SDK saw the
    /// device away. Core Location's EXIT that follows is delivered, untimed. The next stay, entered
    /// and left by real crossings, is timed again.
    @Test
    func heldOutsideFixLeavesTheNextExitUntimedAndTheReentryTimed() async throws {
        let setup = await makeSetup()
        await setup.crossing(.enter)
        let first = try #require(await setup.storage.getDwellVisit(geofenceId: Self.circle.id))
        setup.advance(30)

        let heldFix = ResolvedFix(latitude: 0.01, longitude: 0, horizontalAccuracy: 10, timestamp: setup.clock.wall)
        await setup.resolver.evaluateAllPolygons(reason: .movement, heldFix: heldFix)
        #expect(await setup.storage.getDwellVisit(geofenceId: Self.circle.id) == nil)

        setup.advance(60)
        await setup.crossing(.exit)
        let untimed = try #require(await setup.exitRows().first)
        #expect(untimed.visitId == nil)
        #expect(untimed.enteredAt == nil)
        #expect(untimed.visitDurationSeconds == nil)
        #expect(untimed.trackEventProperties["visitDurationSeconds"] == nil)

        // Past the EXIT cooldown, so the next EXIT is delivered too.
        setup.advance(GeofenceConstants.eventCooldownInterval + 1)
        let reentry = setup.clock.wall
        await setup.crossing(.enter)
        let second = try #require(await setup.storage.getDwellVisit(geofenceId: Self.circle.id))
        setup.advance(90)
        await setup.crossing(.exit)

        // Read as written: each track flushes the older rows it did not write to the event bus,
        // which drains them from the outbox, so the untimed row is gone by now.
        let rows = await setup.exitRows().filter { $0.timestamp > reentry }
        try #require(rows.count == 1)
        let timed = rows[0]
        #expect(second.visitId != first.visitId)
        #expect(timed.visitId == second.visitId)
        #expect(timed.enteredAt.map { Int($0.timeIntervalSince1970) } == Int(reentry.timeIntervalSince1970))
        #expect(timed.visitDurationSeconds == 90)
        #expect(timed.trackEventProperties["visitDurationSeconds"] as? Int == 90)
        #expect(timed.detectionSource == "native")
        #expect(timed.transitionId != second.visitId)
        #expect(await setup.outbox.rows().filter { $0.transition != .exit }.isEmpty)
    }

    /// Control: without outside evidence, the same stay is timed on its EXIT.
    @Test
    func exitWithoutOutsideEvidenceIsTimed() async throws {
        let setup = await makeSetup()
        let enteredAt = setup.clock.wall
        await setup.crossing(.enter)
        setup.advance(90)

        await setup.crossing(.exit)

        let rows = await setup.exitRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitDurationSeconds == 90)
        #expect(rows[0].enteredAt.map { Int($0.timeIntervalSince1970) } == Int(enteredAt.timeIntervalSince1970))
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

        /// A Core Location crossing of the circle now, as the monitor binder hands it on.
        func crossing(_ transition: GeofenceTransition) async {
            await resolver.handleTransition(
                identifier: ExitDurationOutsideEvidenceOutboxTests.circle.id, transition: transition,
                occurredAt: clock.wall, receivedForUserId: "user-1"
            )
        }

        func exitRows() async -> [PendingGeofenceMetric] {
            await outbox.rows().filter { $0.transition == .exit }.sorted { $0.timestamp < $1.timestamp }
        }
    }

    private func makeSetup() async -> Setup {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = GeofenceStorage(fileManager: .default, directoryURL: directory)
        await storage.setCachedGeofences([Self.circle])
        await storage.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: [Self.circle.id])
        let contextStore = BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        contextStore.setUserId("user-1")
        let clock = ManualGeofenceClock(wall: Date())
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
            notificationCenter: notificationCenter, freshFixProvider: { nil }, clock: clock,
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
