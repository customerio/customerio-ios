import CioInternalCommon
import CoreLocation
import Foundation

/// Owns durable continuous visits. A deadline only requests evidence; it never proves membership.
@MainActor
final class GeofenceDwellCoordinator {
    private let transitionEmitter: GeofenceTransitionEmitting
    private var dwellEmissionsInFlight: Set<String> = []
    // `internal`, not `private`, only because the `+Evidence` extension file uses them.
    let storage: GeofenceStorage
    let contextStore: BackgroundDeliveryContextStore
    let fixResolver: MovementFixResolver
    let notificationCenter: NotificationCenter
    let freshFixProvider: (() async -> CLLocation?)?
    let evidenceRetryDelay: TimeInterval
    let maxEvidenceRetryAttempts: Int
    /// The pending evidence request per geofence: the deadline, or a bounded retry after it.
    var deadlineTasks: [String: Task<Void, Never>] = [:]
    var evidenceRetries: [String: EvidenceRetryState] = [:]
    var foregroundObserver: NSObjectProtocol?
    var polygonVerifier: ((String) async -> Void)?

    init(
        storage: GeofenceStorage,
        transitionEmitter: GeofenceTransitionEmitting,
        contextStore: BackgroundDeliveryContextStore,
        logger: Logger,
        fixResolver: MovementFixResolver? = nil,
        notificationCenter: NotificationCenter = .default,
        freshFixProvider: (() async -> CLLocation?)? = nil,
        evidenceRetryDelay: TimeInterval = 60,
        maxEvidenceRetryAttempts: Int = 3
    ) {
        self.storage = storage
        self.transitionEmitter = transitionEmitter
        self.contextStore = contextStore
        self.notificationCenter = notificationCenter
        self.freshFixProvider = freshFixProvider
        self.evidenceRetryDelay = evidenceRetryDelay
        self.maxEvidenceRetryAttempts = max(0, maxEvidenceRetryAttempts)
        self.fixResolver = fixResolver ?? MovementFixResolver(
            logger: logger,
            backgroundTaskRunner: GeofenceBackgroundTime.runner(name: "io.customer.geofence.dwell-fix"),
            desiredAccuracy: kCLLocationAccuracyNearestTenMeters
        )
        registerForegroundEvaluation()
    }

    deinit {
        deadlineTasks.values.forEach { $0.cancel() }
        if let foregroundObserver { notificationCenter.removeObserver(foregroundObserver) }
    }

    @discardableResult
    func handleBoundary(
        geofence: Geofence,
        transition: GeofenceTransition,
        occurredAt: Date,
        expectedUserId: String? = nil,
        detectionSource: String? = nil
    ) async -> GeofenceExitContext? {
        if let expectedUserId, contextStore.currentUserId != expectedUserId { return nil }
        switch transition {
        case .enter:
            await startVisitIfNeeded(
                geofence: geofence,
                enteredAt: occurredAt,
                expectedUserId: expectedUserId
            )
            return nil
        case .exit:
            let result = await exitContext(
                geofence: geofence,
                exitedAt: occurredAt,
                detectionSource: detectionSource ?? (geofence.vertices == nil ? "native" : "location_evidence"),
                expectedUserId: expectedUserId
            )
            // A delayed exit from an older visit must not clear a newer visit.
            guard result.shouldEndVisit else { return nil }
            cancelEvidence(for: geofence.id)
            await storage.removeDwellVisit(geofenceId: geofence.id)
            return result.context
        case .dwell:
            return nil
        }
    }

    /// Accept only evidence already validated against the real shape by the caller.
    /// - Parameters:
    ///   - beginsNewVisit: the evidence is an observed entry. Otherwise, with no visit stored, it
    ///     starts a candidate that supports dwell but no EXIT duration.
    ///   - continuingVisitId: evidence requested for this visit only. If that visit has ended by
    ///     the time the evidence is applied, the evidence is dropped rather than starting another.
    func recordInsideEvidence(
        geofence: Geofence,
        at observedAt: Date,
        source: String,
        expectedUserId: String? = nil,
        beginsNewVisit: Bool = false,
        continuingVisitId: String? = nil
    ) async {
        guard tracksVisit(geofence),
              let userId = contextStore.currentUserId, !userId.isEmpty,
              expectedUserId == nil || expectedUserId == userId,
              let visit = await visitForEvidence(
                  geofence: geofence, observedAt: observedAt, userId: userId,
                  beginsNewVisit: beginsNewVisit, continuingVisitId: continuingVisitId
              )
        else { return }
        await emitDwellIfQualified(
            geofence: geofence, visit: visit, observedAt: observedAt, source: source, userId: userId
        )
    }

    /// The visit inside evidence applies to: the stored one, or a new one when there is none or
    /// the evidence is an observed entry no older than it. Nil when the evidence must be dropped.
    private func visitForEvidence(
        geofence: Geofence,
        observedAt: Date,
        userId: String,
        beginsNewVisit: Bool,
        continuingVisitId: String?
    ) async -> GeofenceDwellVisit? {
        let stored = await currentVisit(geofence: geofence, userId: userId)
        if let continuingVisitId, stored?.visitId != continuingVisitId { return nil }
        if let stored, !beginsNewVisit || stored.enteredAt > observedAt { return stored }
        let visit = GeofenceDwellVisit(
            visitId: UUID().uuidString,
            enteredAt: observedAt,
            geometryRevision: geofence.dwellRevision,
            userId: userId,
            emitted: false,
            entryObserved: beginsNewVisit
        )
        guard await storage.saveDwellVisit(visit, geofenceId: geofence.id) else { return nil }
        scheduleDeadline(for: geofence, visit: visit)
        return visit
    }

    private func emitDwellIfQualified(
        geofence: Geofence,
        visit: GeofenceDwellVisit,
        observedAt: Date,
        source: String,
        userId: String
    ) async {
        guard geofence.dwellThresholdSeconds > 0, !visit.emitted, observedAt >= visit.enteredAt else { return }
        let duration = max(0, Int(observedAt.timeIntervalSince(visit.enteredAt)))
        guard duration >= geofence.dwellThresholdSeconds else { return }
        guard contextStore.currentUserId == userId else { return }
        guard dwellEmissionsInFlight.insert(visit.visitId).inserted else { return }
        defer { dwellEmissionsInFlight.remove(visit.visitId) }
        let persisted = await transitionEmitter.trackDwell(
            geofenceId: geofence.id,
            occurredAt: observedAt,
            context: GeofenceDwellContext(
                visitId: visit.visitId,
                enteredAt: visit.enteredAt,
                thresholdSeconds: geofence.dwellThresholdSeconds,
                durationSeconds: duration,
                detectionSource: source
            ),
            expectedUserId: userId
        )
        guard persisted else { return }
        // The emitter suspends, so an EXIT and a re-entry may have replaced this visit meanwhile.
        // Writing the captured copy back would resurrect the old visit over the new one.
        switch await storage.markDwellVisitEmitted(visit, geofenceId: geofence.id) {
        case .marked:
            cancelEvidence(for: geofence.id)
        case .writeFailed:
            scheduleEvidenceRetry(for: geofence, visit: visit)
        case .superseded:
            // Evidence scheduling now belongs to whatever visit replaced this one.
            break
        }
    }

    private func startVisitIfNeeded(
        geofence: Geofence,
        enteredAt: Date,
        expectedUserId: String?
    ) async {
        guard tracksVisit(geofence),
              let userId = contextStore.currentUserId, !userId.isEmpty,
              expectedUserId == nil || expectedUserId == userId
        else {
            cancelEvidence(for: geofence.id)
            await storage.removeDwellVisit(geofenceId: geofence.id)
            return
        }
        if let existing = await currentVisit(
            geofence: geofence,
            userId: userId
        ) {
            scheduleDeadline(for: geofence, visit: existing)
            return
        }
        let visit = GeofenceDwellVisit(
            visitId: UUID().uuidString,
            enteredAt: enteredAt,
            geometryRevision: geofence.dwellRevision,
            userId: userId,
            emitted: false
        )
        if contextStore.currentUserId == userId,
           await storage.saveDwellVisit(visit, geofenceId: geofence.id) {
            scheduleDeadline(for: geofence, visit: visit)
        }
    }

    /// The stored visit, when it still belongs to `userId` and the fence's current geometry.
    /// A stale one is removed. Internal for the `+Evidence` extension.
    func currentVisit(
        geofence: Geofence,
        userId: String
    ) async -> GeofenceDwellVisit? {
        guard let visit = await storage.getDwellVisit(geofenceId: geofence.id) else { return nil }
        guard visit.userId == userId,
              visit.geometryRevision == geofence.dwellRevision
        else {
            await storage.removeDwellVisit(geofenceId: geofence.id)
            return nil
        }
        return visit
    }

    private func exitContext(
        geofence: Geofence,
        exitedAt: Date,
        detectionSource: String,
        expectedUserId: String?
    ) async -> (context: GeofenceExitContext?, shouldEndVisit: Bool) {
        guard let userId = contextStore.currentUserId, !userId.isEmpty,
              expectedUserId == nil || expectedUserId == userId
        else { return (nil, false) }
        guard let visit = await currentVisit(
            geofence: geofence,
            userId: userId
        ) else {
            return (nil, true)
        }
        guard exitedAt >= visit.enteredAt else { return (nil, false) }
        guard visit.entryObserved, geofence.transitionTypes.contains(.exit) else { return (nil, true) }
        return (
            GeofenceExitContext(
                visitId: visit.visitId,
                enteredAt: visit.enteredAt,
                durationSeconds: Int(exitedAt.timeIntervalSince(visit.enteredAt)),
                detectionSource: detectionSource
            ),
            true
        )
    }

    private func tracksVisit(_ geofence: Geofence) -> Bool {
        geofence.dwellThresholdSeconds > 0 || geofence.transitionTypes.contains(.exit)
    }

    /// Resume persisted candidates after a process relaunch. A due deadline requests fresh
    /// evidence immediately; it does not itself prove the device remained inside.
    func resumePendingVisits(geofences: [Geofence]) async {
        guard let userId = contextStore.currentUserId, !userId.isEmpty else { return }
        for geofence in geofences where tracksVisit(geofence) {
            if let visit = await currentVisit(geofence: geofence, userId: userId) {
                scheduleDeadline(for: geofence, visit: visit)
            }
        }
    }

    /// Monitoring stopped being trustworthy, so persisted entry time can no longer support a
    /// dwell or completed duration. Pending deliveries remain untouched.
    func invalidateContinuity(geofenceId: String? = nil) async {
        if let geofenceId {
            cancelEvidence(for: geofenceId)
            await storage.removeDwellVisit(geofenceId: geofenceId)
            return
        }
        deadlineTasks.values.forEach { $0.cancel() }
        deadlineTasks.removeAll()
        evidenceRetries.removeAll()
        await storage.clearDwellVisits()
    }
}

extension DIGraphShared {
    @MainActor
    var geofenceDwellCoordinator: GeofenceDwellCoordinator {
        let overridden: GeofenceDwellCoordinator? = getOverriddenInstance()
        return overridden ?? GeofenceDwellCoordinator.shared
    }
}

extension GeofenceDwellCoordinator {
    @MainActor
    static let shared = GeofenceDwellCoordinator(
        storage: DIGraphShared.shared.geofenceStorage,
        transitionEmitter: DIGraphShared.shared.geofenceEventTracker,
        contextStore: DIGraphShared.shared.backgroundDeliveryContextStore,
        logger: DIGraphShared.shared.logger
    )
}
