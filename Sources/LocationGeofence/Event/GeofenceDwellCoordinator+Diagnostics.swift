import Foundation

/// Opt-in dwell diagnostics, split from the coordinator's visit lifecycle so both stay under the
/// file cap. Records say what the coordinator did and when, never where or for whom; nothing reads
/// them back to decide anything.
extension GeofenceDwellCoordinator {
    /// Stamped from `clock` directly: `readClock` also tracks wall-clock steps, and recording must
    /// not change what the coordinator observes.
    func recordDiagnostic(
        _ event: DwellDiagnosticEvent,
        fenceId: String? = nil,
        deadlineUptime: TimeInterval? = nil,
        reason: DwellDiagnosticReason? = nil
    ) {
        submitDiagnostic(event, fenceId: fenceId, deadlineUptime: deadlineUptime, reason: reason, token: nil)
    }

    /// For a record about a cause judged before an await: `capturedToken` is the journal generation
    /// read where it was judged, so a clear since then drops the record. Nil records nothing. The
    /// recorder's own nil means the generation now, so a cause that no longer belongs to the current
    /// identity must come through here.
    func recordDiagnostic(
        _ event: DwellDiagnosticEvent,
        capturedToken: UInt64?,
        fenceId: String? = nil,
        deadlineUptime: TimeInterval? = nil,
        reason: DwellDiagnosticReason? = nil
    ) {
        guard let capturedToken else { return }
        submitDiagnostic(event, fenceId: fenceId, deadlineUptime: deadlineUptime, reason: reason, token: capturedToken)
    }

    /// The generation `visit`'s records belong to, read now and synchronously. Nil without a
    /// recorder, or once the visit no longer belongs to the current identity (after a sign-out or
    /// another identify). The clear for that change may already have run, and the visit's records
    /// must not outlive it.
    func diagnosticToken(for visit: GeofenceDwellVisit) -> UInt64? {
        guard let diagnosticRecorder,
              contextStore.currentUserId == visit.userId,
              !identityTracker.interrupted(visit)
        else { return nil }
        return diagnosticRecorder.token
    }

    private func submitDiagnostic(
        _ event: DwellDiagnosticEvent,
        fenceId: String?,
        deadlineUptime: TimeInterval?,
        reason: DwellDiagnosticReason?,
        token: UInt64?
    ) {
        guard let diagnosticRecorder,
              let record = DwellDiagnosticRecord(
                  event: event, atUptime: clock.read().uptime, fenceId: fenceId,
                  deadlineUptime: deadlineUptime, reason: reason
              )
        else { return }
        diagnosticRecorder.record(record, token: token)
    }

    /// Marks a new evidence wait pending until it fires, so only a wait that never fired is
    /// reported cancelled. Recorded under the generation its state captured. Returns that
    /// generation for the wait to record under when it fires, so a reset in between drops that
    /// record too.
    func scheduledDiagnosticDeadline(geofenceId: String, due: TimeInterval) -> UInt64? {
        evidenceRetries[geofenceId]?.pendingDueUptime = due
        let token = evidenceRetries[geofenceId]?.diagnosticToken
        recordDiagnostic(.deadlineScheduled, capturedToken: token, fenceId: geofenceId, deadlineUptime: due)
        return token
    }

    func diagnosticDeadlineFired(geofenceId: String, due: TimeInterval, token: UInt64?) {
        evidenceRetries[geofenceId]?.pendingDueUptime = nil
        recordDiagnostic(.deadlineReached, capturedToken: token, fenceId: geofenceId, deadlineUptime: due)
    }

    /// The due uptime of a wait still pending, read before a cancel removes it.
    func unfiredDiagnosticDeadline(geofenceId: String) -> TimeInterval? {
        deadlineTasks[geofenceId] == nil ? nil : evidenceRetries[geofenceId]?.pendingDueUptime
    }

    /// Hands an identity change to the recorder, which compares the identity in force with the one its
    /// records are kept for, and the journal with its stored owner, clearing history kept for any other.
    /// Judged by version and lineage, never by event dates, before any await. A change another writer
    /// synced first is not cleared again, so records made since survive; the same identity, or a
    /// relaunch under it, keeps the history.
    func clearDiagnosticsIfIdentityChanged() {
        diagnosticRecorder?.syncIdentity()
    }

    /// A sign-out reset that was not superseded: the history was the signed-out user's. Rechecked
    /// here on the main actor, so a sign-in since keeps its records; its identity change clears the rest.
    func clearDiagnosticsIfSignedOut() {
        guard contextStore.currentUserId?.isEmpty ?? true else { return }
        diagnosticRecorder?.invalidateAndClear()
    }
}
