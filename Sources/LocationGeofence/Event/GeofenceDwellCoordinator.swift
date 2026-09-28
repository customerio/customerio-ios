import CioInternalCommon
import CoreLocation
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Owns durable continuous visits. A deadline only requests evidence; it never proves membership.
@MainActor
final class GeofenceDwellCoordinator {
    private let storage: GeofenceStorage
    private let transitionEmitter: GeofenceTransitionEmitting
    private let contextStore: BackgroundDeliveryContextStore
    private let fixResolver: MovementFixResolver
    private let notificationCenter: NotificationCenter
    private let freshFixProvider: (() async -> CLLocation?)?
    private let evidenceRetryDelay: TimeInterval
    private let maxEvidenceRetryAttempts: Int
    private var deadlineTasks: [String: Task<Void, Never>] = [:]
    private var evidenceRetries: [String: EvidenceRetryState] = [:]
    private var dwellEmissionsInFlight: Set<String> = []
    private var foregroundObserver: NSObjectProtocol?
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
              expectedUserId == nil || expectedUserId == userId
        else { return }
        var visit = await currentVisit(geofence: geofence, userId: userId)
        if let continuingVisitId, visit?.visitId != continuingVisitId { return }
        if beginsNewVisit, (visit?.enteredAt ?? .distantPast) <= observedAt {
            visit = nil
        }
        if visit == nil {
            visit = GeofenceDwellVisit(
                visitId: UUID().uuidString,
                enteredAt: observedAt,
                geometryRevision: geofence.dwellRevision,
                userId: userId,
                emitted: false,
                entryObserved: beginsNewVisit
            )
            guard await storage.saveDwellVisit(visit!, geofenceId: geofence.id) else { return }
            scheduleDeadline(for: geofence, visit: visit!)
        }
        guard geofence.dwellThresholdSeconds > 0 else { return }
        guard let visit, !visit.emitted else { return }
        guard observedAt >= visit.enteredAt else { return }
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

    private func currentVisit(
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

    private func scheduleDeadline(for geofence: Geofence, visit: GeofenceDwellVisit) {
        deadlineTasks.removeValue(forKey: geofence.id)?.cancel()
        evidenceRetries[geofence.id] = EvidenceRetryState(visitId: visit.visitId, attempts: 0)
        guard geofence.dwellThresholdSeconds > 0, !visit.emitted else {
            cancelEvidence(for: geofence.id)
            return
        }
        let delay = min(
            TimeInterval(GeofenceDwellLimits.maxThresholdSeconds),
            max(0, visit.enteredAt.addingTimeInterval(TimeInterval(geofence.dwellThresholdSeconds)).timeIntervalSinceNow)
        )
        let delayNanoseconds = UInt64(delay * 1000000000)
        deadlineTasks[geofence.id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled, let self else { return }
            await self.requestQualifyingEvidence(geofenceId: geofence.id)
        }
    }

    func requestQualifyingEvidence(geofenceId: String) async {
        guard !Task.isCancelled,
              let geofence = await storage.getRegisteredGeofence(id: geofenceId),
              !Task.isCancelled,
              let expectedUserId = contextStore.currentUserId, !expectedUserId.isEmpty,
              let visit = await activeVisit(geofence: geofence, userId: expectedUserId),
              !Task.isCancelled
        else {
            cancelEvidence(for: geofenceId)
            return
        }
        if geofence.vertices != nil {
            guard let polygonVerifier else {
                scheduleEvidenceRetry(for: geofence, visit: visit)
                return
            }
            await polygonVerifier(geofenceId)
            guard !Task.isCancelled, contextStore.currentUserId == expectedUserId else { return }
            guard let remaining = await currentVisit(
                geofence: geofence,
                userId: expectedUserId
            ) else {
                cancelEvidence(for: geofenceId)
                return
            }
            guard !remaining.emitted else {
                cancelEvidence(for: geofenceId)
                return
            }
            // A long evidence gap can restart the candidate and schedule its own deadline. Do not
            // let the old visit cancel or replace the new visit's task.
            if remaining.visitId == visit.visitId {
                scheduleEvidenceRetry(for: geofence, visit: remaining)
            }
            return
        }
        let fix = await freshFix()
        guard !Task.isCancelled,
              contextStore.currentUserId == expectedUserId,
              let remaining = await activeVisit(
                  geofence: geofence, userId: expectedUserId, visitId: visit.visitId
              ),
              !Task.isCancelled
        else { return }
        guard let fix else {
            scheduleEvidenceRetry(for: geofence, visit: remaining)
            return
        }
        let center = CLLocation(latitude: geofence.latitude, longitude: geofence.longitude)
        let distance = fix.distance(from: center)
        // The point alone is not a verdict. Only an accuracy circle wholly inside the region is
        // qualifying dwell evidence. Ambiguous or outside fixes leave teardown to Core Location's
        // real EXIT callback so a noisy deadline fix cannot end a live visit.
        guard fix.horizontalAccuracy > 0,
              distance + fix.horizontalAccuracy <= geofence.radius
        else {
            if fix.horizontalAccuracy > 0,
               distance - fix.horizontalAccuracy >= geofence.radius {
                await invalidateContinuity(geofenceId: geofence.id)
                return
            }
            scheduleEvidenceRetry(for: geofence, visit: remaining)
            return
        }
        await recordInsideEvidence(
            geofence: geofence,
            at: fix.timestamp,
            source: "location_evidence",
            expectedUserId: expectedUserId,
            // An EXIT can land during the storage hops before this is applied. The fix predates
            // it, so it must not start a new visit that outlives the exit.
            continuingVisitId: visit.visitId
        )
        guard !Task.isCancelled, contextStore.currentUserId == expectedUserId else { return }
        guard let remaining = await currentVisit(
            geofence: geofence,
            userId: expectedUserId
        ) else {
            cancelEvidence(for: geofence.id)
            return
        }
        guard !remaining.emitted else {
            cancelEvidence(for: geofence.id)
            return
        }
        // Expiring an old visit above can create a new candidate and schedule its deadline. The
        // old request must not cancel or replace that new visit's task.
        if remaining.visitId == visit.visitId {
            scheduleEvidenceRetry(for: geofence, visit: remaining)
        }
    }

    private func freshFix() async -> CLLocation? {
        if let freshFixProvider { return await freshFixProvider() }
        return await withCheckedContinuation { continuation in
            fixResolver.resolve(cached: fixResolver.latestFix, purpose: .pendingEvents) { location, isFresh in
                guard isFresh, location != nil else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: self.fixResolver.latestFix)
            }
        }
    }

    private func activeVisit(
        geofence: Geofence,
        userId: String,
        visitId: String? = nil
    ) async -> GeofenceDwellVisit? {
        guard contextStore.currentUserId == userId,
              let visit = await currentVisit(
                  geofence: geofence,
                  userId: userId
              ),
              !visit.emitted,
              visitId == nil || visit.visitId == visitId
        else { return nil }
        return visit
    }

    private func scheduleEvidenceRetry(for geofence: Geofence, visit: GeofenceDwellVisit) {
        var state = evidenceRetries[geofence.id]
        if state?.visitId != visit.visitId {
            state = EvidenceRetryState(visitId: visit.visitId, attempts: 0)
        }
        guard var state, state.attempts < maxEvidenceRetryAttempts else {
            deadlineTasks.removeValue(forKey: geofence.id)?.cancel()
            return
        }
        state.attempts += 1
        evidenceRetries[geofence.id] = state
        deadlineTasks.removeValue(forKey: geofence.id)?.cancel()
        let delay = max(0, evidenceRetryDelay)
        deadlineTasks[geofence.id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1000000000))
            guard !Task.isCancelled, let self else { return }
            await self.requestQualifyingEvidence(geofenceId: geofence.id)
        }
    }

    private func cancelEvidence(for geofenceId: String) {
        deadlineTasks.removeValue(forKey: geofenceId)?.cancel()
        evidenceRetries.removeValue(forKey: geofenceId)
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

    private func registerForegroundEvaluation() {
        #if canImport(UIKit)
        foregroundObserver = notificationCenter.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task {
                    let geofences = await self.storage.getCachedGeofences()
                    for geofence in geofences where geofence.dwellThresholdSeconds > 0 {
                        if let visit = await self.storage.getDwellVisit(geofenceId: geofence.id), !visit.emitted {
                            // Re-arm from wall-clock entry rather than requesting now: a due visit
                            // still requests immediately, but pre-threshold evidence cannot qualify
                            // and would spend the bounded retries, leaving no deadline at all.
                            self.scheduleDeadline(for: geofence, visit: visit)
                        }
                    }
                }
            }
        }
        #endif
    }

    private struct EvidenceRetryState {
        let visitId: String
        var attempts: Int
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
