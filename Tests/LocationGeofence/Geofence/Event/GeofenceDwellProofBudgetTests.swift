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
        // The retry it replaced was due at 300 too, so wait for the re-armed check itself: it
        // confirms the last charge saved, and ends once it has parked its own retry.
        try #require(await settleOnMain {
            rig.coordinator.unsavedProofCharges.isEmpty
                && rig.coordinator.evidenceRetries[BudgetRig.circle.id]?.activeRequest == nil
                && rig.scheduler.nextDeadline == 300
        })
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

    /// A membership request is already in flight when the dwell deadline fires. The dwell check
    /// joins it at the resolver's issuing boundary, so it issues and is charged nothing, and the
    /// shared fix still proves the dwell.
    @Test
    func dwellCheckJoiningAMembershipRequest_isNotCharged() async throws {
        let rig = await BudgetRig.make(polygon: true)
        defer { rig.close() }
        try await rig.enterPolygon()
        let entryRequests = rig.requestTimes.count
        rig.advance(to: 50)
        rig.holdAnswers = true
        let membership = Task {
            await rig.resolver.evaluateMembership(geofenceIds: [BudgetRig.polygon.id], reason: .movement, requiresFreshFix: true)
        }
        try #require(await settleOnMain { rig.requestTimes.count == entryRequests + 1 })

        rig.advance(to: 60)
        // The deadline's check has run and is waiting on the shared request.
        try #require(await settleOnMain { rig.coordinator.proofLedgers.values.first?.checks == 1 })
        await settleQuietly(0.1)
        rig.provider.handleDeliveredFix(rig.insideFix(at: 60))
        _ = await membership.value

        #expect(await settleOnMain { rig.emitter.dwells.count == 1 })
        #expect(rig.requestTimes.count == entryRequests + 1, "the dwell check joined, issuing nothing")
        #expect(await rig.visit()?.dwellProofAttempts == 0)
    }

    /// The resolver asks admission exactly when it would issue a request: never for a current
    /// cached answer or one joining a request in flight, always for a stale cache. A refusal
    /// issues nothing and answers at once.
    @Test
    func resolverAsksAdmissionOnlyAsItIssues() {
        let dateUtil = DateUtilStub()
        dateUtil.givenNow = Date(timeIntervalSince1970: 5000)
        let resolver = MovementFixResolver(logger: LoggerMock(), dateUtil: dateUtil, waitForTimeout: { _ in
            try? await Task.sleep(nanoseconds: 60000000000)
        })
        var issued = 0, asked = 0
        resolver.requestFreshFix = { issued += 1 }
        resolver.cancelFreshFix = {}
        func fix(age: TimeInterval) -> CLLocation {
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 2), altitude: 0,
                horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: dateUtil.now.addingTimeInterval(-age)
            )
        }
        var answers: [Bool] = []

        resolver.resolve(cached: fix(age: 5), purpose: .pendingEvents, admit: { asked += 1
            return true
        }) { _, fresh in answers.append(fresh) }
        #expect(asked == 0 && issued == 0 && answers == [true], "a current cached answer is free")

        resolver.resolve(cached: fix(age: 60), purpose: .pendingEvents, admit: { asked += 1
            return false
        }) { _, fresh in answers.append(fresh) }
        #expect(asked == 1 && issued == 0 && answers == [true, false], "a refused request is not issued")

        resolver.resolve(cached: fix(age: 60), purpose: .pendingEvents, admit: { asked += 1
            return true
        }) { _, fresh in answers.append(fresh) }
        #expect(asked == 2 && issued == 1, "a stale cache issues, and is admitted, at once")
        resolver.resolve(cached: nil, purpose: .pendingEvents, admit: { asked += 1
            return true
        }) { _, fresh in answers.append(fresh) }
        #expect(asked == 2 && issued == 1, "joining the request in flight is free")

        resolver.handleDeliveredFix(fix(age: 0))
        #expect(answers == [true, false, true, true])
    }

    /// A dwell evidence request cancelled, or superseded by another, before its request is issued
    /// is refused at the issuing boundary and spends nothing.
    @Test
    func cancelledOrSupersededEvidenceRequest_isRefusedAsItWouldIssue() async throws {
        let rig = await BudgetRig.make(polygon: false)
        defer { rig.close() }
        await rig.enterCircle()
        let visit = try #require(await rig.visit())
        let coordinator = rig.coordinator!
        let request = try #require(coordinator.beginEvidenceRequest(geofenceId: BudgetRig.circle.id, visit: visit))

        let cancelled = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return GeofenceDwellEvidenceScope.$request.withValue(request) { coordinator.dwellProofAdmission()?() }
        }
        #expect(await cancelled.value == false)
        #expect(coordinator.proofLedgers[visit.visitId]?.attempts == 0)

        coordinator.finishEvidenceRequest(request)
        _ = coordinator.beginEvidenceRequest(geofenceId: BudgetRig.circle.id, visit: visit)
        let superseded = GeofenceDwellEvidenceScope.$request.withValue(request) { coordinator.dwellProofAdmission()?() }
        #expect(superseded == false)
        #expect(coordinator.proofLedgers[visit.visitId]?.attempts == 0)
    }

    /// The fourth request proves the dwell and reserves it, but its outbox write fails. The
    /// delivery needs no location, so the spent budget does not stop its retry.
    @Test
    func reservedDwellAfterTheLastRequest_stillRetriesItsDelivery() async throws {
        let rig = await BudgetRig.make(polygon: false)
        defer { rig.close() }
        await rig.enterCircle()
        rig.answers = [nil, nil, nil, rig.insideFix(at: 420)]
        rig.emitter.failingDeliveries = 1
        await rig.drive(to: 420)
        try #require(rig.emitter.deliveries.count == 1 && rig.emitter.dwells.isEmpty)
        #expect(rig.scheduler.nextDeadline == 540)

        await rig.drive(to: 600)

        #expect(rig.emitter.dwells.map(\.occurredAt) == [rig.at(420)])
        #expect(rig.requestTimes == [60, 180, 300, 420])
        #expect(await rig.visit()?.dwellProofAttempts == 4)
    }

    /// Every check is answered from a fix the SDK already holds, so none is charged; the chain
    /// still stops after eight checks rather than running for as long as the process does.
    @Test
    func freeAnswers_stopAfterTheCheckLimit() async throws {
        let rig = await BudgetRig.make(polygon: false)
        defer { rig.close() }
        await rig.enterCircle()
        rig.beforeEachDeadline = { [rig] moment in rig.provider.handleDeliveredFix(rig.vagueFix(at: moment)) }
        await rig.drive(to: 2000)

        #expect(rig.requestTimes.isEmpty)
        let visit = try #require(await rig.visit())
        #expect(visit.dwellProofChecks == 8)
        #expect(visit.dwellProofAttempts == 0)
        #expect(rig.coordinator.deadlineTasks[BudgetRig.circle.id] == nil)
        #expect(rig.exhaustionLogs() == 1)
    }

    /// The first request's charge could not be saved. No second request is admitted on top of it,
    /// so a process dying now would lose only that one; once the save goes through, the next is.
    @Test
    func unsavedCharge_holdsBackTheNextRequestUntilItIsSaved() async throws {
        let rig = await BudgetRig.make(polygon: false)
        defer { rig.close() }
        await rig.enterCircle()
        await rig.storage.setLedgerSaveFails(true)
        await rig.drive(to: 60)
        try #require(rig.requestTimes == [60])
        #expect(rig.coordinator.unsavedProofCharges.count == 1)

        await rig.drive(to: 180)
        #expect(rig.requestTimes == [60], "no request is admitted on top of an unsaved charge")
        #expect(await rig.visit()?.dwellProofAttempts == 0)

        await rig.storage.setLedgerSaveFails(false)
        await rig.drive(to: 300)
        #expect(rig.requestTimes == [60, 300])
        #expect(await rig.visit()?.dwellProofAttempts == 2)
        // The new charge stays unconfirmed until the save before the next admission.
        let visitId = try #require(await rig.visit()?.visitId)
        await rig.coordinator.persistProofLedger(geofenceId: BudgetRig.circle.id, visitId: visitId)
        #expect(rig.coordinator.unsavedProofCharges.isEmpty)
    }

    /// Each refused request is recorded with its own reason, apart from a request that came back
    /// empty: a charge not yet saved, a request too soon after the last, and a spent budget.
    @Test
    func refusals_recordTheirOwnReasons() async throws {
        let unsaved = await BudgetRig.make(polygon: false, diagnostics: true)
        defer { unsaved.close() }
        await unsaved.enterCircle()
        await unsaved.storage.setLedgerSaveFails(true)
        await unsaved.drive(to: 180)
        try #require(unsaved.requestTimes == [60])
        #expect(try await unsaved.rejectionReasons() == ["noFix", "chargeUnsaved"])

        let early = await BudgetRig.make(polygon: false, diagnostics: true)
        defer { early.close() }
        await early.enterCircle()
        await early.drive(to: 60)
        await early.drive(to: 100)
        await early.coordinator.rearmPendingEvidence(includePolygons: false)
        // The retry it replaced was due at 180 too: wait for the re-armed check to have been refused.
        try #require(await settleOnMain {
            let state = early.coordinator.evidenceRetries[BudgetRig.circle.id]
            return state?.refusal == .tooSoon && state?.activeRequest == nil
        })
        try #require(early.requestTimes == [60])
        #expect(try await early.rejectionReasons() == ["noFix", "tooSoon"])

        let spent = await BudgetRig.make(polygon: false, diagnostics: true)
        defer { spent.close() }
        await spent.enterCircle()
        await spent.drive(to: 2000)
        try #require(spent.requestTimes == [60, 180, 300, 420])
        #expect(try await spent.rejectionReasons().last == "proofBudgetSpent")
    }

    /// The stored state cannot be read when the unsaved charge is confirmed. That is not a visit
    /// gone: the charge stays unconfirmed, so admission keeps refusing until a save goes through.
    @Test
    func unreadableState_doesNotConfirmAnUnsavedCharge() async throws {
        let rig = await BudgetRig.make(polygon: false)
        defer { rig.close() }
        await rig.enterCircle()
        await rig.storage.setLedgerSaveFails(true)
        await rig.drive(to: 60)
        try #require(rig.requestTimes == [60])
        let visitId = try #require(await rig.visit()?.visitId)
        await rig.storage.setLedgerSaveFails(false)

        let stateFile = rig.root.appendingPathComponent("geofenceState.json")
        let saved = try Data(contentsOf: stateFile)
        try Data("not a state".utf8).write(to: stateFile)
        await rig.coordinator.persistProofLedger(geofenceId: BudgetRig.circle.id, visitId: visitId)
        #expect(rig.coordinator.unsavedProofCharges == [visitId])

        try saved.write(to: stateFile)
        await rig.coordinator.persistProofLedger(geofenceId: BudgetRig.circle.id, visitId: visitId)
        #expect(rig.coordinator.unsavedProofCharges.isEmpty)
        #expect(await rig.visit()?.dwellProofAttempts == 1)
    }

    /// A covering crossing is held for a long-threshold polygon visit while membership passes keep
    /// finding the device inside. None of them can qualify the stay before its threshold, so none
    /// replaces the threshold deadline with an earlier retry, and no check is counted until then.
    @Test
    func heldCrossingBeforeTheThreshold_neitherMovesTheDeadlineNorCountsChecks() async throws {
        let rig = await BudgetRig.make(polygon: true, threshold: 600)
        defer { rig.close() }
        rig.answers = [rig.insideFix(at: 0)]
        _ = await rig.resolver.evaluateMembership(geofenceIds: [BudgetRig.polygon.id], reason: .foreground, requiresFreshFix: true)
        try #require(await settleOnMain { rig.scheduler.nextDeadline == 600 })
        try #require(await settleOnMain { rig.coordinator.polygonIdsLoaded })
        rig.coordinator.noteEnter(geofenceId: BudgetRig.polygon.id, occurredAt: rig.at(0), crossing: true)
        try #require(rig.coordinator.heldCoveringCrossings[BudgetRig.polygon.id] != nil)

        for moment in stride(from: 60.0, through: 540, by: 60) {
            rig.advance(to: moment)
            rig.answers = [rig.insideFix(at: moment)]
            _ = await rig.resolver.evaluateMembership(geofenceIds: [BudgetRig.polygon.id], reason: .movement, requiresFreshFix: true)
            await settleQuietly(0.05)
            #expect(rig.scheduler.nextDeadline == 600, "an inside pass at \(moment) s moved the deadline")
        }
        #expect(rig.coordinator.proofLedgers.values.allSatisfy { $0.checks == 0 })
        #expect(await rig.visit()?.dwellProofChecks == 0)
        #expect(rig.emitter.dwells.isEmpty)
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
    /// Leaves each request pending, for `provider.handleDeliveredFix` to answer.
    var holdAnswers = false
    /// Runs at each deadline `drive` reaches, once the clock reads it and before it fires.
    var beforeEachDeadline: ((TimeInterval) -> Void)?
    private(set) var requestTimes: [TimeInterval] = []
    private var now: TimeInterval = 0
    private var exhaustionLogsBeforeRelaunch = 0
    /// Records dwell diagnostics to `root` when the rig was made with them on.
    let diagnostics: DwellDiagnosticRecorder

    private init(polygon: Bool, diagnostics: Bool) {
        self.polygon = polygon
        let clock = ManualGeofenceClock(wall: start)
        self.clock = clock
        self.diagnostics = DwellDiagnosticRecorder(
            journal: DwellDiagnosticJournal(directory: root, isEnabled: { diagnostics }),
            isEnabled: diagnostics, now: { clock.read().uptime }
        )
        dateUtil.givenNow = start
        self.storage = GeofenceStorage(fileManager: .default, directoryURL: root, dateUtil: dateUtil)
        self.context = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: root)
        context.setUserId("budget-user")
    }

    static func make(polygon: Bool, threshold: Int = 60, diagnostics: Bool = false) async -> BudgetRig {
        let rig = BudgetRig(polygon: polygon, diagnostics: diagnostics)
        let base = polygon ? Self.polygon : Self.circle
        let fence = Geofence(
            id: base.id, latitude: base.latitude, longitude: base.longitude, radius: base.radius, name: base.name,
            transitionTypes: base.transitionTypes, lastUpdated: base.lastUpdated, vertices: base.vertices,
            dwellThresholdSeconds: threshold
        )
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
            guard !holdAnswers else { return }
            guard !answers.isEmpty, let fix = answers.removeFirst() else {
                provider.handleRequestFailure()
                return
            }
            provider.handleDeliveredFix(fix)
        }
        let coordinator = GeofenceDwellCoordinator(
            storage: storage, transitionEmitter: emitter, contextStore: context, logger: logger,
            fixResolver: provider, notificationCenter: notificationCenter, clock: clock, diagnosticRecorder: diagnostics,
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
            advance(to: next, before: beforeEachDeadline)
            // Until the request it ran has scheduled its retry; one that schedules none, the
            // last, waits out the timeout.
            _ = await settleOnMain(timeout: 1) { (self.scheduler.nextDeadline ?? 0) > next }
            await settleQuietly(0.05)
        }
        advance(to: moment)
        await settleQuietly(0.1)
    }

    func advance(to moment: TimeInterval, before: ((TimeInterval) -> Void)? = nil) {
        now = max(now, moment)
        clock.advance(to: at(now))
        dateUtil.givenNow = clock.wall
        before?(now)
        scheduler.advance(to: now)
    }

    /// A fix at the fence's centre whose accuracy circle is far wider than it: it decides nothing.
    func vagueFix(at seconds: TimeInterval) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0.25, longitude: 0.25),
            altitude: 0, horizontalAccuracy: 500, verticalAccuracy: 500, timestamp: at(seconds)
        )
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

    /// The reasons of the rejections the journal holds, oldest first.
    func rejectionReasons() async throws -> [String] {
        await diagnostics.drain()
        let data = try Data(contentsOf: DwellDiagnosticJournal.fileURL(in: root))
        let document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try #require(document["records"] as? [[String: Any]])
        return rows.filter { $0["event"] as? String == "dwellRejected" }.compactMap { $0["reason"] as? String }
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
    /// Every delivery attempt, failed or not.
    private(set) var deliveries: [Date] = []
    /// Deliveries still to fail, as an outbox write would.
    var failingDeliveries = 0

    func trackTransition(geofenceId: String, transition: GeofenceTransition, occurredAt: Date) async {}

    func trackExit(
        geofenceId: String, occurredAt: Date, context: GeofenceExitContext?, expectedUserId: String?
    ) async {}

    func trackDwell(
        geofenceId: String, occurredAt: Date, context: GeofenceDwellContext, expectedUserId: String?
    ) async -> Bool {
        deliveries.append(occurredAt)
        guard failingDeliveries == 0 else {
            failingDeliveries -= 1
            return false
        }
        dwells.append(Dwell(occurredAt: occurredAt))
        return true
    }
}
