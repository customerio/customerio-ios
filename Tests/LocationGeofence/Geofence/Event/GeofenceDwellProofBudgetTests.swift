@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
import CoreLocation
import Foundation
import SharedTests
import Testing
#if canImport(UIKit)
import UIKit
#endif

/// The per-visit dwell-proof budget: four location requests, the deadline's first and its retries,
/// persisted on the visit so no re-arm, resume or relaunch replenishes it, issued at least 120 s
/// apart. Membership passes the SDK runs for other reasons are neither charged nor refused, and a
/// qualifying fix one of them returns still proves the dwell. Deadlines and retries run on a
/// scripted scheduler; only Core Location's answers and time are scripted.
@Suite("Dwell proof budget", .serialized)
@MainActor
struct GeofenceDwellProofBudgetTests {
    /// A foreground return re-arms the visit mid-chain. The four requests are still all, each at
    /// least 120 s after the one before, and the visit's persisted count says so.
    @Test
    func foregroundRearm_doesNotReplenishTheBudgetOrShortenTheSpacing() async throws {
        let rig = await BudgetRig.make(polygon: false)
        defer { rig.close() }
        await rig.enterCircle()
        await rig.drive(to: 60)
        await rig.drive(to: 180)
        try #require(rig.requestTimes == [60, 180])

        await rig.drive(to: 200)
        rig.foreground()
        // The re-armed deadline is due at once; its request is held back to 120 s after the last.
        try #require(await settleOnMain { rig.scheduler.nextDeadline == 300 })
        await rig.drive(to: 2000)

        #expect(rig.requestTimes == [60, 180, 300, 420])
        #expect(zip(rig.requestTimes, rig.requestTimes.dropFirst()).allSatisfy { $1 - $0 >= 120 })
        #expect(await rig.visit()?.dwellProofAttempts == 4)
        #expect(rig.coordinator.deadlineTasks[BudgetRig.circle.id] == nil)
        #expect(rig.exhaustionLogs() == 1)
    }

    /// The process dies after two requests; the next one resumes the visit from disk. It may issue
    /// only the two left, and the first of them waits out the spacing since the old process's last.
    @Test
    func relaunch_readsThePersistedCountAndSpacing() async throws {
        let rig = await BudgetRig.make(polygon: false)
        defer { rig.close() }
        await rig.enterCircle()
        await rig.drive(to: 180)
        try #require(rig.requestTimes == [60, 180])

        await rig.drive(to: 200)
        await rig.relaunch()
        await rig.coordinator.resumePendingVisits(geofences: [BudgetRig.circle])
        // Due at once, its request is held back to 120 s after the old process's last.
        try #require(await settleOnMain { rig.scheduler.nextDeadline == 300 })
        await rig.drive(to: 2000)

        #expect(rig.requestTimes == [60, 180, 300, 420])
        #expect(await rig.visit()?.dwellProofAttempts == 4)
        #expect(rig.coordinator.deadlineTasks[BudgetRig.circle.id] == nil)
        #expect(rig.emitter.dwells.isEmpty)
    }

    /// With the budget spent, re-arms request nothing. A membership pass the SDK runs for another
    /// reason is neither refused nor charged, and its qualifying fix still proves the dwell.
    @Test
    func exhaustedPolygon_requestsNothingMore_butAMembershipPassStillProvesTheDwell() async throws {
        let rig = await BudgetRig.make(polygon: true)
        defer { rig.close() }
        try await rig.enterPolygon()
        let entryRequests = rig.requestTimes.count
        await rig.drive(to: 1000)
        try #require(rig.requestTimes.dropFirst(entryRequests) == [60, 180, 300, 420])
        #expect(await rig.visit()?.dwellProofAttempts == 4)
        #expect(rig.exhaustionLogs() == 1)

        await rig.coordinator.rearmPendingEvidence(includePolygons: true)
        await rig.drive(to: 1100)
        #expect(rig.requestTimes.count == entryRequests + 4)
        #expect(rig.exhaustionLogs() == 1, "logged once per visit")

        rig.answers = [rig.insideFix(at: 1100)]
        let decided = await rig.resolver.evaluateMembership(
            geofenceIds: [BudgetRig.polygon.id], reason: .movement, requiresFreshFix: true
        )
        #expect(decided)
        #expect(rig.requestTimes.count == entryRequests + 5)
        #expect(rig.emitter.dwells.map(\.occurredAt) == [rig.at(1100)])
        #expect(await rig.visit()?.dwellProofAttempts == 4)
    }

    /// The early short retry keeps its shortfall-sized wait, clamped to 30–60 s, and counts.
    @Test
    func shortRetry_isClampedAndCounted() async throws {
        let rig = await BudgetRig.make(polygon: false)
        defer { rig.close() }
        await rig.enterCircle()
        rig.answers = [rig.insideFix(at: 59)]
        await rig.drive(to: 60)

        #expect(rig.scheduler.nextDeadline == 90, "one second short waits the 30 s floor")
        #expect(await rig.visit()?.dwellProofAttempts == 1)
        rig.answers = [rig.insideFix(at: 90)]
        await rig.drive(to: 90)
        #expect(rig.requestTimes == [60, 90])
        #expect(await rig.visit()?.dwellProofAttempts == 2)
        #expect(rig.emitter.dwells.map(\.occurredAt) == [rig.at(90)])
    }

    /// A visit stored before the budget existed decodes with none spent.
    @Test
    func visitPersistedBeforeTheBudget_decodesWithNoneSpent() throws {
        let reading = GeofenceClockReading(wall: Date(timeIntervalSince1970: 1000), uptime: 50, boot: .init(bootTime: 950, processToken: nil))
        var visit = GeofenceDwellVisit(
            visitId: "v", enteredAt: reading.wall, geometryRevision: "r", userId: "u", emitted: false,
            timing: GeofenceVisitTiming(enteredAt: reading.wall, recordedAt: reading)
        )
        visit.dwellProofAttempts = 3
        visit.lastDwellProofRequest = reading
        let encoder = JSONEncoder()
        var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(visit)) as? [String: Any])
        #expect(object["dwellProofAttempts"] as? Int == 3)
        object.removeValue(forKey: "dwellProofAttempts")
        object.removeValue(forKey: "lastDwellProofRequest")

        let decoded = try JSONDecoder().decode(GeofenceDwellVisit.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.dwellProofAttempts == 0)
        #expect(decoded.lastDwellProofRequest == nil)
        #expect(try JSONDecoder().decode(GeofenceDwellVisit.self, from: encoder.encode(visit)).dwellProofAttempts == 3)
    }

    /// On its timeout, the resolver tells Core Location to stop the request, rather than only
    /// answering its callers; a request answered in time is not cancelled.
    @Test
    func requestTimeout_cancelsTheRequest() async {
        let resolver = MovementFixResolver(logger: LoggerMock(), dateUtil: DateUtilStub(), waitForTimeout: { _ in })
        var cancels = 0
        resolver.requestFreshFix = {}
        resolver.cancelFreshFix = { cancels += 1 }
        var answers: [Bool] = []
        resolver.resolve(cached: nil, purpose: .pendingEvents) { _, isFresh in answers.append(isFresh) }
        #expect(await settleOnMain { answers == [false] })
        #expect(cancels == 1)

        let dateUtil = DateUtilStub()
        let answered = MovementFixResolver(logger: LoggerMock(), dateUtil: dateUtil, waitForTimeout: { _ in
            try? await Task.sleep(nanoseconds: 50000000)
        })
        var answeredCancels = 0
        answered.requestFreshFix = { [weak answered] in
            answered?.handleDeliveredFix(CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 2), altitude: 0,
                horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: dateUtil.now
            ))
        }
        answered.cancelFreshFix = { answeredCancels += 1 }
        var answeredFresh: [Bool] = []
        answered.resolve(cached: nil, purpose: .pendingEvents) { _, isFresh in answeredFresh.append(isFresh) }
        await settleQuietly(0.2)
        #expect(answeredFresh == [true])
        #expect(answeredCancels == 0)
    }
}

/// A coordinator, fix resolver and polygon resolver over one storage directory, with a scripted
/// scheduler and clock. Every request goes through `MovementFixResolver`'s request seam, so the
/// budget sees exactly what Core Location would be asked.
@MainActor
private final class BudgetRig {
    static let circle = Geofence(
        id: "budget-circle", latitude: 0.25, longitude: 0.25, radius: 100, name: "circle",
        transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1), dwellThresholdSeconds: 60
    )
    static let polygon = Geofence(
        id: "budget-polygon", latitude: 0.25, longitude: 0.25, radius: 100, name: "polygon",
        transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1),
        vertices: [
            LocationData(latitude: 0, longitude: 0),
            LocationData(latitude: 0, longitude: 1),
            LocationData(latitude: 1, longitude: 0)
        ],
        dwellThresholdSeconds: 60
    )

    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let start = Date(timeIntervalSince1970: 2000000)
    let clock: ManualGeofenceClock
    let dateUtil = DateUtilStub()
    let storage: GeofenceStorage
    let context: BackgroundDeliveryContextStore
    let emitter = BudgetEmitter()
    let polygon: Bool
    private(set) var scheduler = ReplayDwellScheduler()
    private(set) var notificationCenter = NotificationCenter()
    private(set) var logger = LoggerMock()
    private(set) var provider: MovementFixResolver!
    private(set) var coordinator: GeofenceDwellCoordinator!
    private(set) var resolver: PolygonMembershipResolver!
    /// Answers for the next requests, in order; an empty list or nil fails the request.
    var answers: [CLLocation?] = []
    private(set) var requestTimes: [TimeInterval] = []
    private var now: TimeInterval = 0
    private var exhaustionLogsBeforeRelaunch = 0

    private init(polygon: Bool) {
        self.polygon = polygon
        self.clock = ManualGeofenceClock(wall: start)
        dateUtil.givenNow = start
        self.storage = GeofenceStorage(fileManager: .default, directoryURL: root, dateUtil: dateUtil)
        self.context = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: root)
        context.setUserId("budget-user")
    }

    static func make(polygon: Bool) async -> BudgetRig {
        let rig = BudgetRig(polygon: polygon)
        let fence = polygon ? Self.polygon : Self.circle
        await rig.storage.setCachedGeofences([fence])
        await rig.storage.recordRegistration(center: LocationData(latitude: 0.25, longitude: 0.25), businessIds: [fence.id])
        rig.launch()
        return rig
    }

    /// A process: its own coordinator, resolvers and scheduler over the shared files and clock.
    private func launch() {
        let scheduler = scheduler
        let provider = MovementFixResolver(logger: LoggerMock(), dateUtil: dateUtil)
        provider.systemCachedFix = { nil }
        provider.requestFreshFix = { [weak self, weak provider] in
            guard let self, let provider else { return }
            requestTimes.append(now)
            guard !answers.isEmpty, let fix = answers.removeFirst() else {
                provider.handleRequestFailure()
                return
            }
            provider.handleDeliveredFix(fix)
        }
        let coordinator = GeofenceDwellCoordinator(
            storage: storage, transitionEmitter: emitter, contextStore: context, logger: logger,
            fixResolver: provider, notificationCenter: notificationCenter, clock: clock,
            waitForEvidence: { delay in try await scheduler.sleep(nanoseconds: delay) }
        )
        resolver = PolygonMembershipResolver(
            storage: storage, transitionEmitter: emitter, logger: LoggerMock(), contextStore: context,
            dateUtil: dateUtil, fixResolver: provider, notificationCenter: NotificationCenter(),
            dwellCoordinator: coordinator
        )
        self.provider = provider
        self.coordinator = coordinator
    }

    /// The process dies: its waits are cancelled and nothing of it is reachable; the files remain.
    func relaunch() async {
        coordinator.cancelAllEvidence()
        scheduler.stop()
        exhaustionLogsBeforeRelaunch += exhaustionLogs()
        scheduler = ReplayDwellScheduler()
        scheduler.advance(to: now)
        notificationCenter = NotificationCenter()
        logger = LoggerMock()
        launch()
        await settleQuietly(0.1)
    }

    func enterCircle() async {
        await coordinator.handleBoundary(geofence: Self.circle, transition: .enter, occurredAt: start)
        await settleQuietly(0.1)
    }

    func enterPolygon() async throws {
        answers = [insideFix(at: 0)]
        _ = await resolver.evaluateMembership(geofenceIds: [Self.polygon.id], reason: .foreground, requiresFreshFix: true)
        try #require(await settleOnMain { self.scheduler.nextDeadline == 60 })
    }

    func foreground() {
        #if canImport(UIKit)
        notificationCenter.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        #else
        Task { await coordinator.rearmPendingEvidence(includePolygons: true) }
        #endif
    }

    /// Runs every deadline due up to `moment`, in order, letting each request and retry land.
    func drive(to moment: TimeInterval) async {
        await settleQuietly(0.1)
        while let next = scheduler.nextDeadline, next <= moment {
            advance(to: next)
            // Until the request it ran has scheduled its retry; one that schedules none, the
            // last, waits out the timeout.
            _ = await settleOnMain(timeout: 1) { (self.scheduler.nextDeadline ?? 0) > next }
            await settleQuietly(0.05)
        }
        advance(to: moment)
        await settleQuietly(0.1)
    }

    private func advance(to moment: TimeInterval) {
        now = max(now, moment)
        clock.advance(to: at(now))
        dateUtil.givenNow = clock.wall
        scheduler.advance(to: now)
    }

    func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    func insideFix(at seconds: TimeInterval) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0.25, longitude: 0.25),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: at(seconds)
        )
    }

    func visit() async -> GeofenceDwellVisit? {
        await storage.getDwellVisit(geofenceId: polygon ? Self.polygon.id : Self.circle.id)
    }

    func exhaustionLogs() -> Int {
        exhaustionLogsBeforeRelaunch + logger.infoReceivedInvocations.filter { $0.message.contains("dwell proof budget exhausted") }.count
    }

    func close() {
        coordinator.cancelAllEvidence()
        scheduler.stop()
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private final class BudgetEmitter: GeofenceTransitionEmitting {
    struct Dwell {
        let occurredAt: Date
    }

    private(set) var dwells: [Dwell] = []

    func trackTransition(geofenceId: String, transition: GeofenceTransition, occurredAt: Date) async {}

    func trackExit(
        geofenceId: String, occurredAt: Date, context: GeofenceExitContext?, expectedUserId: String?
    ) async {}

    func trackDwell(
        geofenceId: String, occurredAt: Date, context: GeofenceDwellContext, expectedUserId: String?
    ) async -> Bool {
        dwells.append(Dwell(occurredAt: occurredAt))
        return true
    }
}
