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
            visitId: visit.visitId, diagnosticToken: diagnosticToken(for: visit)
        )
        guard state.visitId == visit.visitId else { return nil }
        let request = GeofenceDwellEvidenceRequest(
            geofenceId: geofenceId, visitId: visit.visitId, token: UUID(), minimumTimestamp: state.nextFixAfter
        )
        state.nextFixAfter = nil
        state.activeFloor = request.minimumTimestamp
        state.earlyEvidence = nil
        state.spacingWait = nil
        state.activeRequest = request.token
        evidenceRetries[geofenceId] = state
        return request
    }

    func finishEvidenceRequest(_ request: GeofenceDwellEvidenceRequest) {
        guard var state = evidenceRetries[request.geofenceId],
              state.visitId == request.visitId, state.activeRequest == request.token
        else { return }
        state.activeRequest = nil
        state.activeFloor = nil
        state.earlyEvidence = nil
        state.spacingWait = nil
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

    /// One short retry, the only exception to the ordinary spacing, waits the measured shortfall
    /// with a margin, clamped to `shortRetryDelayRange`; its request is charged to the visit's
    /// budget like any other. Re-arming the same visit retains its used flag; a new visit starts
    /// with its own budget. Other rejections keep the ordinary spacing.
    func shortEvidenceRetryDelay(geofenceId: String, state: inout EvidenceRetryState) -> TimeInterval? {
        guard !Task.isCancelled, !state.shortRetryUsed,
              let request = GeofenceDwellEvidenceScope.request,
              request.geofenceId == geofenceId, request.visitId == state.visitId,
              state.activeRequest == request.token, let early = state.earlyEvidence
        else { return nil }
        state.shortRetryUsed = true
        state.nextFixAfter = early.timestamp
        state.earlyEvidence = nil
        // Give the provider a small margin beyond the measured shortfall. Qualification still uses
        // the returned fix's date.
        return min(Self.shortRetryDelayRange.upperBound, max(Self.shortRetryDelayRange.lowerBound, early.shortfall + 1))
    }

    /// The early short retry's wait: never sooner than 30 s after the request it follows, never
    /// later than 60 s.
    static let shortRetryDelayRange: ClosedRange<TimeInterval> = 30 ... 60

    /// Location requests a visit may issue to prove its dwell: the deadline's first, then its
    /// retries. Membership passes the SDK runs for other reasons are not counted.
    var dwellProofBudget: Int {
        maxEvidenceRetryAttempts + 1
    }

    /// Reserves one of the visit's dwell-proof requests before one is issued on its behalf, inside
    /// a dwell evidence request (`GeofenceDwellEvidenceScope`). Outside one — a membership pass for
    /// a wake, an ENTER or an EXIT — nothing is charged or refused. Only an issued request is
    /// spaced: a cached answer, or one joining a request in flight, is neither charged nor held
    /// back. A request too soon after the visit's last is held back, and its retry waits out the
    /// rest of the spacing: the ordinary `dwellProofSpacing`, or for the short retry, whose request
    /// carries a newer-measurement floor, the lower bound of `shortRetryDelayRange`.
    /// - Returns: whether the request may be issued.
    func reserveDwellProofRequest() async -> Bool {
        guard let request = GeofenceDwellEvidenceScope.request else { return true }
        let spacing = min(dwellProofSpacing, request.minimumTimestamp != nil ? Self.shortRetryDelayRange.lowerBound : .infinity)
        let outcome = await storage.reserveDwellProofAttempt(
            geofenceId: request.geofenceId, visitId: request.visitId, limit: dwellProofBudget,
            spacing: spacing, at: readClock()
        )
        guard case .tooSoon(let remaining) = outcome else { return outcome == .reserved }
        if var state = evidenceRetries[request.geofenceId], state.visitId == request.visitId,
           state.activeRequest == request.token {
            state.spacingWait = remaining
            evidenceRetries[request.geofenceId] = state
        }
        return false
    }

    /// `visit` has spent its dwell-proof budget: no deadline or retry asks for another location,
    /// and its collection lease goes. A qualifying fix the SDK obtains for another reason can
    /// still prove the dwell. Logged once per visit.
    func proofBudgetExhausted(geofenceId: String, visit: GeofenceDwellVisit) {
        deadlineTasks.removeValue(forKey: geofenceId)?.cancel()
        releaseCollectionLease(geofenceId: geofenceId, ifVisit: visit.visitId)
        if exhaustedProofBudgetsLogged.insert(visit.visitId).inserted {
            logger.geofenceDwellProofBudgetExhausted(geofenceId: geofenceId, requests: visit.dwellProofAttempts)
        }
    }

    func freshFix(newerThan minimumTimestamp: Date? = nil) async -> CLLocation? {
        // With a minimum, only an answer strictly newer than it counts, so a retry after an early
        // measurement is never answered by that same measurement from the cache.
        let newEnough: (CLLocation?) -> CLLocation? = { fix in
            guard let minimumTimestamp, let fix else { return fix }
            return fix.timestamp > minimumTimestamp ? fix : nil
        }
        // Charged only when a request would be issued: a cached answer, or one joining a request
        // already in flight, costs nothing. The test provider stands for a request every time.
        if let freshFixProvider {
            guard await reserveDwellProofRequest() else { return nil }
            let provided = await freshFixProvider()
            return newEnough(provided)
        }
        let cached = minimumTimestamp == nil ? fixResolver.latestFix : nil
        if fixResolver.wouldIssueRequest(cached: cached) {
            guard await reserveDwellProofRequest() else { return nil }
        }
        return await withCheckedContinuation { continuation in
            fixResolver.resolve(cached: cached, purpose: .pendingEvents) { location, isFresh in
                guard isFresh, location != nil else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: newEnough(self.fixResolver.latestFix))
            }
        }
    }
}
