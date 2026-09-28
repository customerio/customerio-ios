import CioInternalCommon
import CoreLocation
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Deadline and retry scheduling for dwell evidence, split from the coordinator's visit lifecycle
/// so both stay under the file cap. Members are `internal` rather than `private` only because of
/// this split; they remain implementation detail of an internal type.
extension GeofenceDwellCoordinator {
    struct EvidenceRetryState {
        let visitId: String
        var attempts: Int
    }

    func scheduleDeadline(for geofence: Geofence, visit: GeofenceDwellVisit) {
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
            await requestPolygonEvidence(geofence: geofence, visit: visit, expectedUserId: expectedUserId)
        } else {
            await requestCircleEvidence(geofence: geofence, visit: visit, expectedUserId: expectedUserId)
        }
    }

    /// A polygon's membership is decided by the resolver against the real shape; its verdict
    /// reaches this coordinator as inside evidence, not through this call's return.
    private func requestPolygonEvidence(
        geofence: Geofence,
        visit: GeofenceDwellVisit,
        expectedUserId: String
    ) async {
        guard let polygonVerifier else {
            scheduleEvidenceRetry(for: geofence, visit: visit)
            return
        }
        await polygonVerifier(geofence.id)
        await retryIfStillPending(geofence: geofence, visitId: visit.visitId, expectedUserId: expectedUserId)
    }

    private func requestCircleEvidence(
        geofence: Geofence,
        visit: GeofenceDwellVisit,
        expectedUserId: String
    ) async {
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
        await retryIfStillPending(geofence: geofence, visitId: visit.visitId, expectedUserId: expectedUserId)
    }

    /// After evidence was applied: stop when the visit ended or emitted, retry while it is the
    /// same visit and still pending.
    private func retryIfStillPending(geofence: Geofence, visitId: String, expectedUserId: String) async {
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
        // Applying the evidence can restart the candidate (a long evidence gap, or an expired old
        // visit) and schedule the new visit's own deadline. The old request must not cancel or
        // replace that new visit's task.
        if remaining.visitId == visitId {
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

    func scheduleEvidenceRetry(for geofence: Geofence, visit: GeofenceDwellVisit) {
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

    func cancelEvidence(for geofenceId: String) {
        deadlineTasks.removeValue(forKey: geofenceId)?.cancel()
        evidenceRetries.removeValue(forKey: geofenceId)
    }

    func registerForegroundEvaluation() {
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
}
