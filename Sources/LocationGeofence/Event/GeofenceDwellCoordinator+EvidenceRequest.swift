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

/// What one visit has spent proving its dwell: location requests issued, evidence checks run, and
/// when the last request was issued. Each count only grows.
struct GeofenceDwellProofLedger: Equatable, Sendable {
    var attempts = 0
    var checks = 0
    var lastRequest: GeofenceClockReading?

    /// This ledger with whatever `visit` persisted that it has not seen: the higher count, and the
    /// later request on one boot (on two, the one recorded since).
    func merged(with visit: GeofenceDwellVisit) -> GeofenceDwellProofLedger {
        var merged = self
        merged.attempts = max(attempts, visit.dwellProofAttempts)
        merged.checks = max(checks, visit.dwellProofChecks)
        if let persisted = visit.lastDwellProofRequest {
            if let last = lastRequest, last.boot.isSameBoot(as: persisted.boot) {
                merged.lastRequest = persisted.uptime > last.uptime ? persisted : last
            } else {
                merged.lastRequest = lastRequest ?? persisted
            }
        }
        return merged
    }
}

/// Request ownership and early-evidence retries, split from the scheduler to keep its file focused.
/// These helpers are internal only so the coordinator's other extension files can call them.
extension GeofenceDwellCoordinator {
    func beginEvidenceRequest(geofenceId: String, visit: GeofenceDwellVisit) -> GeofenceDwellEvidenceRequest? {
        var state = evidenceRetries[geofenceId] ?? EvidenceRetryState(
            visitId: visit.visitId, diagnosticToken: diagnosticToken(for: visit)
        )
        guard state.visitId == visit.visitId else { return nil }
        // Seeded from what the visit persisted, so admission needs no storage read.
        proofLedgers[visit.visitId] = proofLedger(for: visit)
        let request = GeofenceDwellEvidenceRequest(
            geofenceId: geofenceId, visitId: visit.visitId, token: UUID(), minimumTimestamp: state.nextFixAfter
        )
        state.nextFixAfter = nil
        state.activeFloor = request.minimumTimestamp
        state.earlyEvidence = nil
        state.spacingWait = nil
        state.refusal = nil
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

    /// Evidence checks a visit's deadline and retries may run, whether a request answered them or
    /// a cached or shared fix did: twice the request budget. It ends a chain that free answers
    /// would otherwise keep alive for as long as the process runs.
    var maxDwellProofChecks: Int {
        2 * dwellProofBudget
    }

    /// What `visit` has spent, as this process counts it, merged with what was persisted.
    func proofLedger(for visit: GeofenceDwellVisit) -> GeofenceDwellProofLedger {
        (proofLedgers[visit.visitId] ?? GeofenceDwellProofLedger()).merged(with: visit)
    }

    /// Whether a visit that needs a location to prove its dwell has spent its requests or its
    /// checks. A reserved dwell needs none: its delivery is never held back by either.
    func proofSpent(_ visit: GeofenceDwellVisit) -> Bool {
        guard visit.dwellReservation == nil else { return false }
        let ledger = proofLedger(for: visit)
        return ledger.attempts >= dwellProofBudget || ledger.checks >= maxDwellProofChecks
    }

    /// What is left of `geofence`'s threshold for `visit` at `reading`, by elapsed time as qualifying
    /// measures it. None for a candidate awaiting proof, whose time has not started, or a reserved
    /// dwell, which only repeats its delivery; across an ambiguous boot no elapsed time is known
    /// to count down from, and the whole threshold remains.
    func thresholdRemaining(for visit: GeofenceDwellVisit, geofence: Geofence, at reading: GeofenceClockReading) -> TimeInterval {
        guard !visit.awaitsPresenceProof, visit.dwellReservation == nil else { return 0 }
        let elapsed = visit.timing?.elapsed(enteredAt: visit.enteredAt, until: reading.wall, at: reading)?.qualifyingSeconds ?? 0
        return min(TimeInterval(GeofenceDwellLimits.maxThresholdSeconds), max(0, TimeInterval(geofence.dwellThresholdSeconds) - elapsed))
    }

    /// Counts one evidence check for `visit`. False, counting nothing, when it has none left.
    func countDwellProofCheck(geofenceId: String, visit: GeofenceDwellVisit) -> Bool {
        guard !proofSpent(visit) else { return false }
        var ledger = proofLedger(for: visit)
        ledger.checks += 1
        updateProofLedger(ledger, geofenceId: geofenceId, visitId: visit.visitId)
        return true
    }

    /// The admission a fix resolver calls at the moment it would issue a request for the dwell
    /// evidence request this task runs (`GeofenceDwellEvidenceScope`); nil outside one, so a
    /// membership pass for a wake, an ENTER or an EXIT is neither charged nor refused. Called only
    /// when a request is about to be issued: a cached answer, or one joining a request in flight,
    /// is neither charged nor held back.
    func dwellProofAdmission() -> (() -> Bool)? {
        guard let request = GeofenceDwellEvidenceScope.request else { return nil }
        return { [weak self] in self?.admitDwellProofRequest(request) ?? false }
    }

    /// Synchronous, at the issuing boundary, so nothing can change between the decision and the
    /// request: refuses a request for a cancelled or superseded evidence request, past the budget,
    /// or too soon after the visit's last — the ordinary `dwellProofSpacing`, or for the short
    /// retry, whose request carries a newer-measurement floor, the lower bound of
    /// `shortRetryDelayRange`; a held-back request's retry waits out the rest. An admitted request
    /// is counted in memory now and persisted after.
    func admitDwellProofRequest(_ request: GeofenceDwellEvidenceRequest) -> Bool {
        guard !Task.isCancelled, var state = evidenceRetries[request.geofenceId],
              state.visitId == request.visitId, state.activeRequest == request.token,
              var ledger = proofLedgers[request.visitId]
        else { return false }
        // Each refusal is noted with its own reason, for the rejection the request's check records.
        guard ledger.attempts < dwellProofBudget else {
            state.refusal = .proofBudgetSpent
            evidenceRetries[request.geofenceId] = state
            return false
        }
        // The previous charge must be on disk first: never one admitted on top of an unsaved one.
        guard !unsavedProofCharges.contains(request.visitId) else {
            state.refusal = .chargeUnsaved
            evidenceRetries[request.geofenceId] = state
            return false
        }
        let reading = readClock()
        let spacing = min(dwellProofSpacing, request.minimumTimestamp != nil ? Self.shortRetryDelayRange.lowerBound : .infinity)
        if let last = ledger.lastRequest, last.boot.isSameBoot(as: reading.boot), reading.uptime >= last.uptime,
           reading.uptime - last.uptime < spacing {
            state.spacingWait = spacing - (reading.uptime - last.uptime)
            state.refusal = .tooSoon
            evidenceRetries[request.geofenceId] = state
            return false
        }
        ledger.attempts += 1
        ledger.lastRequest = reading
        unsavedProofCharges.insert(request.visitId)
        updateProofLedger(ledger, geofenceId: request.geofenceId, visitId: request.visitId)
        return true
    }

    /// Keeps `ledger` as `visitId`'s and starts saving it at once, off the main actor, so a request
    /// in flight when the process dies is normally already on disk. Only the confirming save
    /// before the next admission (`persistProofLedger`) clears the visit's unsaved charge.
    private func updateProofLedger(_ ledger: GeofenceDwellProofLedger, geofenceId: String, visitId: String) {
        proofLedgers[visitId] = ledger
        dirtyProofLedgers.insert(visitId)
        Task.detached { [storage] in
            await storage.recordDwellProofLedger(geofenceId: geofenceId, visitId: visitId, ledger: ledger)
        }
    }

    /// Before each evidence request, while the visit has a charge not yet confirmed saved: saves
    /// its ledger, a background save notwithstanding, so a failed save is retried before anything
    /// else is admitted. Once the store holds every charge counted so far, the unsaved charge
    /// clears; a failed save leaves it, and admission refuses. With no unsaved charge it does
    /// nothing and does not suspend, so concurrent checks keep their order. The persisted copy only
    /// grows.
    func persistProofLedger(geofenceId: String, visitId: String) async {
        guard unsavedProofCharges.contains(visitId), dirtyProofLedgers.contains(visitId), let ledger = proofLedgers[visitId],
              await storage.recordDwellProofLedger(geofenceId: geofenceId, visitId: visitId, ledger: ledger),
              let current = proofLedgers[visitId]
        else { return }
        if current == ledger { dirtyProofLedgers.remove(visitId) }
        if ledger.attempts >= current.attempts { unsavedProofCharges.remove(visitId) }
    }

    /// `visit` has spent its dwell-proof requests or checks: no deadline or retry asks for another
    /// location, and its collection lease goes. A qualifying fix the SDK obtains for another reason
    /// can still prove the dwell. Logged once per visit.
    func proofBudgetExhausted(geofenceId: String, visit: GeofenceDwellVisit) {
        deadlineTasks.removeValue(forKey: geofenceId)?.cancel()
        releaseCollectionLease(geofenceId: geofenceId, ifVisit: visit.visitId)
        if exhaustedProofBudgetsLogged.insert(visit.visitId).inserted {
            let ledger = proofLedger(for: visit)
            logger.geofenceDwellProofBudgetExhausted(geofenceId: geofenceId, requests: ledger.attempts, checks: ledger.checks)
        }
    }

    func freshFix(newerThan minimumTimestamp: Date? = nil) async -> CLLocation? {
        // With a minimum, only an answer strictly newer than it counts, so a retry after an early
        // measurement is never answered by that same measurement from the cache.
        let newEnough: (CLLocation?) -> CLLocation? = { fix in
            guard let minimumTimestamp, let fix else { return fix }
            return fix.timestamp > minimumTimestamp ? fix : nil
        }
        // Charged only as a request is issued (`dwellProofAdmission`): a cached answer, or one
        // joining a request already in flight, costs nothing. The test provider stands for a
        // request every time.
        let admit = dwellProofAdmission()
        if let freshFixProvider {
            if let admit, !admit() { return nil }
            let provided = await freshFixProvider()
            return newEnough(provided)
        }
        return await withCheckedContinuation { continuation in
            fixResolver.resolve(
                cached: minimumTimestamp == nil ? fixResolver.latestFix : nil, purpose: .pendingEvents, admit: admit
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
