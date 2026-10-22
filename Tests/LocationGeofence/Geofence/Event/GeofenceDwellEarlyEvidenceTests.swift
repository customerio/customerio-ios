@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
import CoreLocation
import Foundation
import SharedTests
import Testing

@Suite("Dwell early evidence", .serialized)
@MainActor
struct GeofenceDwellEarlyEvidenceTests {
    @Test(arguments: [false, true])
    func deadline_givenPreThresholdInsideFix_thenRetriesSoonWithNewMeasurement(polygon: Bool) async throws {
        let rig = await EarlyDwellRig.make(polygon: polygon)
        defer { rig.close() }
        try await rig.enter()
        let initialRequests = rig.requests
        rig.answers = [rig.fix(at: 56.6), rig.fix(at: 90)]

        rig.advance(to: 60)
        try #require(await settleOnMain {
            rig.requests == initialRequests + 1 && rig.scheduler.pendingCount == 1
        })
        #expect(rig.emitter.dwells.isEmpty)
        let retry = try #require(rig.scheduler.nextDeadline)
        try #require(abs(retry - 90) < 0.001, "a slightly early fix waits the short floor, not the spacing: \(retry)")

        rig.advance(to: retry)
        try #require(await settleOnMain { rig.emitter.dwells.count == 1 })
        #expect(rig.requests == initialRequests + 2, "the retry must request a newer measurement")
        #expect(rig.emitter.dwells.first?.occurredAt == rig.at(90))
        #expect(await rig.storage.getDwellVisit(geofenceId: rig.geofence.id)?.emitted == true)
    }

    @Test(arguments: [false, true])
    func retry_givenDepartureAfterEarlyFix_thenEndsVisitWithoutDwell(polygon: Bool) async throws {
        let rig = await EarlyDwellRig.make(polygon: polygon)
        defer { rig.close() }
        try await rig.enter()
        rig.answers = [rig.fix(at: 56.6), rig.fix(at: 90, inside: false)]
        let retry = try await rig.firstShortRetry()

        rig.advance(to: retry)
        try #require(await rig.waitForVisitToEnd())
        #expect(rig.emitter.dwells.isEmpty)
        #expect(await rig.storage.getDwellVisit(geofenceId: rig.geofence.id) == nil)
    }

    /// No answer at the short retry, which can be neither fresh nor early once it waits at least
    /// 30 s past a 60 s threshold, so ordinary spacing resumes and the four requests are all.
    @Test(arguments: [false, true])
    func retry_givenNoFixesAfterShortRetry_thenKeepsNormalBackoffAndRequestBudget(polygon: Bool) async throws {
        let rig = await EarlyDwellRig.make(polygon: polygon)
        defer { rig.close() }
        try await rig.enter()
        let initialRequests = rig.requests
        rig.answers = [rig.fix(at: 56.6), nil, nil, nil]
        var moment = try await rig.firstShortRetry()

        for attempt in 2 ... 4 {
            rig.advance(to: moment)
            try #require(await settleOnMain {
                rig.requests == initialRequests + attempt &&
                    (attempt == 4 ? rig.scheduler.pendingCount == 0 : rig.scheduler.pendingCount == 1)
            })
            if attempt < 4 {
                let next = try #require(rig.scheduler.nextDeadline)
                #expect(abs(next - moment - 120) < 0.001, "only the first early answer gets a short retry")
                moment = next
            }
        }
        #expect(rig.requests == initialRequests + 4)
        #expect(rig.emitter.dwells.isEmpty)
    }

    @Test(arguments: [false, true])
    func rearm_givenShortRetryAlreadyUsed_thenSameVisitDoesNotGainAnother(polygon: Bool) async throws {
        let rig = await EarlyDwellRig.make(polygon: polygon)
        defer { rig.close() }
        try await rig.enter()
        rig.answers = [rig.fix(at: 56.6), nil]
        let retry = try await rig.firstShortRetry()
        rig.advance(to: retry)
        try #require(await settleOnMain { rig.scheduler.pendingCount == 1 })

        await rig.coordinator.rearmPendingEvidence(includePolygons: true)

        try #require(await settleOnMain {
            guard let due = rig.scheduler.nextDeadline else { return false }
            return abs(due - retry - 120) < 0.001
        }, "rearming the same visit must not grant another short retry, nor shorten the spacing")
        #expect(rig.emitter.dwells.isEmpty)
    }

    @Test(arguments: [false, true])
    func deadline_givenEarlierMovementEvidenceThenNoFix_thenPreservesDeadlineAndNormalRetry(polygon: Bool) async throws {
        let rig = await EarlyDwellRig.make(polygon: polygon)
        defer { rig.close() }
        try await rig.enter()
        rig.advance(to: 30)
        await rig.coordinator.recordInsideEvidence(
            geofence: rig.geofence, at: rig.at(29), source: "location_evidence"
        )
        #expect(rig.scheduler.nextDeadline == 60)
        rig.answers = [nil]

        rig.advance(to: 60)

        try #require(await settleOnMain { rig.scheduler.nextDeadline == 180 })
        #expect(rig.emitter.dwells.isEmpty)
    }

    @Test
    func rearm_givenShortRetryStillPending_thenUsesItsNewMeasurementRequirement() async throws {
        let rig = await EarlyDwellRig.make(polygon: false)
        defer { rig.close() }
        try await rig.enter()
        rig.answers = [rig.fix(at: 56.6), rig.fix(at: 90)]
        let retry = try await rig.firstShortRetry()

        await rig.coordinator.rearmPendingEvidence(includePolygons: true)
        // The replaced wait is withdrawn, and the re-armed one registered, asynchronously.
        await settleQuietly(0.2)
        try #require(rig.scheduler.pendingCount == 1 && rig.scheduler.nextDeadline == retry, "a re-arm keeps the short retry's floor")
        rig.advance(to: retry)

        try #require(await settleOnMain { rig.emitter.dwells.count == 1 })
        #expect(rig.requests == 2, "rearming must not reuse the rejected cached measurement")
        #expect(rig.emitter.dwells.first?.occurredAt == rig.at(90))
    }

    @Test
    func polygonDeadline_givenRecentMovementFix_thenStillRequestsFreshEvidence() async throws {
        let rig = await EarlyDwellRig.make(polygon: true)
        defer { rig.close() }
        try await rig.enter()
        rig.advance(to: 50)
        rig.answers = [rig.fix(at: 50)]
        _ = await rig.resolver.evaluateMembership(
            geofenceIds: [rig.geofence.id], reason: .foreground, requiresFreshFix: false
        )
        let before = rig.requests
        rig.answers = [rig.fix(at: 56.6), rig.fix(at: 90)]

        let retry = try await rig.firstShortRetry()
        rig.advance(to: retry)

        try #require(await settleOnMain { rig.emitter.dwells.count == 1 })
        #expect(rig.requests == before + 2, "neither dwell request may reuse the ten-second-old movement fix")
        #expect(rig.emitter.dwells.first?.occurredAt == rig.at(90))
    }

    @Test
    func rearm_givenShortRetryWaitingForProvider_thenStillRequiresNewerMeasurement() async throws {
        let rig = await EarlyDwellRig.make(polygon: false)
        defer { rig.close() }
        try await rig.enter()
        rig.answers = [rig.fix(at: 56.6)]
        let retry = try await rig.firstShortRetry()
        rig.holdAnswers = true
        rig.advance(to: retry)
        try #require(await settleOnMain { rig.requests == 2 })
        let previousLogs = rig.providerLogCount

        await rig.coordinator.rearmPendingEvidence(includePolygons: true)
        try #require(await settleOnMain { rig.providerLogCount > previousLogs })
        rig.provider.handleDeliveredFix(rig.fix(at: 90))

        try #require(
            await settleOnMain { rig.emitter.dwells.count == 1 },
            "a rearm must join the newer-fix request instead of accepting the old cached fix"
        )
        #expect(rig.emitter.dwells.first?.occurredAt == rig.at(90))
    }

    @Test
    func request_givenConcurrentMovementRejection_thenNoFixKeepsNormalBackoff() async throws {
        let rig = await EarlyDwellRig.make(polygon: false)
        defer { rig.close() }
        try await rig.enter()
        rig.holdAnswers = true
        rig.advance(to: 60)
        try #require(await settleOnMain { rig.requests == 1 })

        await rig.coordinator.recordInsideEvidence(
            geofence: rig.geofence, at: rig.at(59), source: "location_evidence"
        )
        rig.provider.handleRequestFailure()

        try #require(await settleOnMain { rig.scheduler.nextDeadline == 180 })
        #expect(rig.emitter.dwells.isEmpty)
    }

    @Test
    func rejection_givenEarlyInsideMeasurement_thenJournalRecordsTimingShortfall() async throws {
        let rig = await EarlyDwellRig.make(polygon: true, diagnostics: true)
        defer { rig.close() }
        try await rig.enter()
        let initialRequests = rig.requests
        rig.answers = [rig.fix(at: 56.6)]
        rig.advance(to: 60)
        try #require(await settleOnMain {
            rig.requests == initialRequests + 1 && rig.scheduler.pendingCount == 1
        })
        await rig.diagnostics.drain()

        let data = try Data(contentsOf: DwellDiagnosticJournal.fileURL(in: rig.root))
        let document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try #require(document["records"] as? [[String: Any]])
        let rejection = try #require(rows.last { ($0["reason"] as? String) == "belowThreshold" })
        let shortfall = try #require(rejection["thresholdShortfall"] as? Double)
        #expect(abs(shortfall - 3.4) < 0.001)
        #expect(rig.emitter.dwells.isEmpty)
    }
}

/// Runs deadlines through the real coordinator, fix resolver and (for polygons) membership resolver.
/// Only Core Location's one-shot answer and the passage of time are scripted.
@MainActor
private final class EarlyDwellRig {
    let root: URL
    let start = Date(timeIntervalSince1970: 1000000)
    let clock: ManualGeofenceClock
    let dateUtil: DateUtilStub
    let scheduler: ReplayDwellScheduler
    let storage: GeofenceStorage
    let context: BackgroundDeliveryContextStore
    let geofence: Geofence
    let coordinator: GeofenceDwellCoordinator
    let resolver: PolygonMembershipResolver
    let provider: MovementFixResolver
    let emitter: EarlyDwellEmitter
    let diagnostics: DwellDiagnosticRecorder
    let providerLogger: LoggerMock
    var answers: [CLLocation?] = []
    var holdAnswers = false
    private(set) var requests = 0
    var providerLogCount: Int { providerLogger.infoReceivedInvocations.count + providerLogger.debugReceivedInvocations.count }

    private init(polygon: Bool, diagnosticEnabled: Bool) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let start = Date(timeIntervalSince1970: 1000000)
        let clock = ManualGeofenceClock(wall: start)
        let dateUtil = DateUtilStub()
        dateUtil.givenNow = start
        let scheduler = ReplayDwellScheduler()
        let storage = GeofenceStorage(fileManager: .default, directoryURL: root, dateUtil: dateUtil)
        let context = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: root)
        context.setUserId("retry-user")
        let emitter = EarlyDwellEmitter()
        let journal = DwellDiagnosticJournal(directory: root, isEnabled: { diagnosticEnabled })
        let diagnostics = DwellDiagnosticRecorder(
            journal: journal, isEnabled: diagnosticEnabled, now: { clock.read().uptime }
        )
        let providerLogger = LoggerMock()
        let provider = MovementFixResolver(logger: providerLogger, dateUtil: dateUtil, diagnosticRecorder: diagnostics)
        provider.systemCachedFix = { nil }
        let coordinator = GeofenceDwellCoordinator(
            storage: storage, transitionEmitter: emitter, contextStore: context, logger: LoggerMock(),
            fixResolver: provider, notificationCenter: NotificationCenter(), clock: clock, diagnosticRecorder: diagnostics,
            waitForEvidence: { delay in try await scheduler.sleep(nanoseconds: delay) }
        )
        let resolver = PolygonMembershipResolver(
            storage: storage, transitionEmitter: emitter, logger: LoggerMock(), contextStore: context,
            dateUtil: dateUtil, fixResolver: provider, notificationCenter: NotificationCenter(),
            dwellCoordinator: coordinator
        )
        self.root = root
        self.clock = clock
        self.dateUtil = dateUtil
        self.scheduler = scheduler
        self.storage = storage
        self.context = context
        self.emitter = emitter
        self.diagnostics = diagnostics
        self.providerLogger = providerLogger
        self.provider = provider
        self.coordinator = coordinator
        self.resolver = resolver
        self.geofence = Self.makeGeofence(polygon: polygon)
        provider.requestFreshFix = { [weak self] in
            self?.deliverNextFix()
        }
    }

    private static func makeGeofence(polygon: Bool) -> Geofence {
        Geofence(
            id: "retry-fence", latitude: 0.25, longitude: 0.25, radius: 100, name: "Retry fence",
            transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1),
            vertices: polygon ? [
                LocationData(latitude: 0, longitude: 0),
                LocationData(latitude: 0, longitude: 1),
                LocationData(latitude: 1, longitude: 0)
            ] : nil, dwellThresholdSeconds: 60
        )
    }

    private func deliverNextFix() {
        requests += 1
        guard !holdAnswers else { return }
        guard !answers.isEmpty, let fix = answers.removeFirst() else {
            provider.handleRequestFailure()
            return
        }
        provider.handleDeliveredFix(fix)
    }

    static func make(polygon: Bool, diagnostics: Bool = false) async -> EarlyDwellRig {
        let rig = EarlyDwellRig(polygon: polygon, diagnosticEnabled: diagnostics)
        await rig.storage.setCachedGeofences([rig.geofence])
        await rig.storage.recordRegistration(
            center: LocationData(latitude: 0.25, longitude: 0.25), businessIds: [rig.geofence.id]
        )
        return rig
    }

    func enter() async throws {
        if geofence.vertices != nil {
            answers = [fix(at: 0)]
            _ = await resolver.evaluateMembership(
                geofenceIds: [geofence.id], reason: .foreground, requiresFreshFix: true
            )
        } else {
            await coordinator.handleBoundary(geofence: geofence, transition: .enter, occurredAt: start)
        }
        try #require(await settleOnMain { self.scheduler.nextDeadline == 60 })
    }

    func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    func firstShortRetry() async throws -> TimeInterval {
        let before = requests
        advance(to: 60)
        try #require(await settleOnMain { self.requests == before + 1 && self.scheduler.pendingCount == 1 })
        let due = try #require(scheduler.nextDeadline)
        try #require(abs(due - 90) < 0.001, "expected a short retry at the 30 s floor, got \(due)")
        #expect(emitter.dwells.isEmpty)
        return due
    }

    func advance(to seconds: TimeInterval) {
        clock.advance(to: at(seconds))
        dateUtil.givenNow = clock.wall
        scheduler.advance(to: seconds)
    }

    func fix(at seconds: TimeInterval, inside: Bool = true) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: inside ? 0.25 : 2, longitude: inside ? 0.25 : 2),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: at(seconds)
        )
    }

    func close() {
        coordinator.cancelEvidence(for: geofence.id)
        scheduler.stop()
        Task { [diagnostics, root] in
            await diagnostics.drain()
            try? FileManager.default.removeItem(at: root)
        }
    }

    func waitForVisitToEnd() async -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if await storage.getDwellVisit(geofenceId: geofence.id) == nil { return true }
            do { try await Task.sleep(nanoseconds: 10000000) } catch { return false }
        }
        return await storage.getDwellVisit(geofenceId: geofence.id) == nil
    }
}

@MainActor
private final class EarlyDwellEmitter: GeofenceTransitionEmitting {
    struct Dwell {
        let occurredAt: Date
        let context: GeofenceDwellContext
    }

    private(set) var dwells: [Dwell] = []

    func trackTransition(geofenceId: String, transition: GeofenceTransition, occurredAt: Date) async {}

    func trackExit(
        geofenceId: String, occurredAt: Date, context: GeofenceExitContext?, expectedUserId: String?
    ) async {}

    func trackDwell(
        geofenceId: String, occurredAt: Date, context: GeofenceDwellContext, expectedUserId: String?
    ) async -> Bool {
        dwells.append(Dwell(occurredAt: occurredAt, context: context))
        return true
    }
}
