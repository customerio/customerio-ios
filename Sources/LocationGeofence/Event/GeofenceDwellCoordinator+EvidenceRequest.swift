import CoreLocation
import Foundation

/// Identifies one request through its async resolver calls, without attributing another task's
/// simultaneous movement evidence to it. The timestamp is only the pending short retry's floor.
struct GeofenceDwellEvidenceRequest: Sendable {
    let geofenceId: String
    let visitId: String
    let token: UUID
    let minimumTimestamp: Date?
}

enum GeofenceDwellEvidenceScope {
    @TaskLocal static var request: GeofenceDwellEvidenceRequest?
}

/// Request ownership and early-evidence retries, split from the scheduler to keep its file focused.
/// These helpers are internal only so the coordinator's other extension files can call them.
extension GeofenceDwellCoordinator {
    func beginEvidenceRequest(geofenceId: String, visit: GeofenceDwellVisit) -> GeofenceDwellEvidenceRequest? {
        var state = evidenceRetries[geofenceId] ?? EvidenceRetryState(
            visitId: visit.visitId, attempts: 0, diagnosticToken: diagnosticToken(for: visit)
        )
        guard state.visitId == visit.visitId else { return nil }
        let request = GeofenceDwellEvidenceRequest(
            geofenceId: geofenceId, visitId: visit.visitId, token: UUID(), minimumTimestamp: state.nextFixAfter
        )
        state.nextFixAfter = nil
        state.earlyEvidence = nil
        state.activeRequest = request.token
        evidenceRetries[geofenceId] = state
        return request
    }

    func finishEvidenceRequest(_ request: GeofenceDwellEvidenceRequest) {
        guard var state = evidenceRetries[request.geofenceId],
              state.visitId == request.visitId, state.activeRequest == request.token
        else { return }
        state.activeRequest = nil
        state.earlyEvidence = nil
        evidenceRetries[request.geofenceId] = state
    }

    func rememberEarlyEvidence(geofenceId: String, visitId: String, timestamp: Date, shortfall: TimeInterval?) {
        guard !Task.isCancelled, let shortfall, shortfall.isFinite, shortfall > 0,
              let request = GeofenceDwellEvidenceScope.request,
              request.geofenceId == geofenceId, request.visitId == visitId,
              var state = evidenceRetries[geofenceId], state.visitId == visitId,
              state.activeRequest == request.token
        else { return }
        state.earlyEvidence = (timestamp, shortfall)
        evidenceRetries[geofenceId] = state
    }

    /// One short retry consumes one of the existing attempts. Re-arming the same visit retains
    /// its used flag; a new visit starts with its own budget. Other rejections keep normal backoff.
    func shortEvidenceRetryDelay(geofenceId: String, state: inout EvidenceRetryState) -> TimeInterval? {
        guard !Task.isCancelled, !state.shortRetryUsed,
              let request = GeofenceDwellEvidenceScope.request,
              request.geofenceId == geofenceId, request.visitId == state.visitId,
              state.activeRequest == request.token, let early = state.earlyEvidence
        else { return nil }
        state.shortRetryUsed = true
        state.nextFixAfter = early.timestamp
        state.earlyEvidence = nil
        // Give the provider a small margin beyond the measured shortfall, without extending the
        // existing retry or collection budget. Qualification still uses the returned fix's date.
        return min(max(0, evidenceRetryDelay), early.shortfall + 1)
    }

    func freshFix(newerThan minimumTimestamp: Date? = nil) async -> CLLocation? {
        // With a minimum, only an answer strictly newer than it counts, so a retry after an early
        // measurement is never answered by that same measurement from the cache.
        let newEnough: (CLLocation?) -> CLLocation? = { fix in
            guard let minimumTimestamp, let fix else { return fix }
            return fix.timestamp > minimumTimestamp ? fix : nil
        }
        if let freshFixProvider {
            let provided = await freshFixProvider()
            return newEnough(provided)
        }
        return await withCheckedContinuation { continuation in
            fixResolver.resolve(
                cached: minimumTimestamp == nil ? fixResolver.latestFix : nil,
                purpose: .pendingEvents
            ) { location, isFresh in
                guard isFresh, location != nil else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: newEnough(self.fixResolver.latestFix))
            }
        }
    }
}
