import CioInternalCommon
import Foundation

/// The duration an EXIT carries, split from the coordinator's visit lifecycle so both stay under
/// the file cap. `internal` rather than `private` only because of this split.
///
/// An EXIT ends a visit by the same order every other boundary uses (`GeofenceExitMark.overtakes`);
/// a duration is only the wall-clock span between two dates both on the visit's own, unbroken
/// timeline, with no outside evidence between them.
extension GeofenceDwellCoordinator {
    /// What an EXIT does to the visit. `endedVisitId` is the visit it read and ends; nil when it
    /// found none, or found one it must leave — a visit that began after this EXIT. `reading` is
    /// the one `exit` was marked at, before any await.
    func exitContext(
        geofence: Geofence,
        exit: GeofenceExitMark,
        processedAt reading: GeofenceClockReading,
        detectionSource: String,
        expectedUserId: String?
    ) async -> (context: GeofenceExitContext?, endedVisitId: String?) {
        guard let userId = contextStore.currentUserId, !userId.isEmpty,
              expectedUserId == nil || expectedUserId == userId
        else { return (nil, nil) }
        let stored = await currentVisit(geofence: geofence, userId: userId)
        let endedByThisExit = takeVisitEndedByPendingExit(geofence: geofence, exit: exit, userId: userId)
        // A delayed exit from an older visit must not clear a newer visit.
        if let stored, exit.overtakes(stored) {
            return (
                exitContext(for: stored, geofence: geofence, exit: exit, processedAt: reading, source: detectionSource),
                stored.visitId
            )
        }
        // The visit this EXIT ends was already replaced by an overlapping re-entry; there is nothing
        // left to remove, but its duration still travels with the EXIT.
        return (
            endedByThisExit.flatMap {
                exitContext(for: $0, geofence: geofence, exit: exit, processedAt: reading, source: detectionSource)
            },
            nil
        )
    }

    /// The duration an EXIT carries for `visit`; nil when the visit's start was not an observed
    /// entry, nothing has yet proved the device there, the customer did not configure EXIT, outside
    /// evidence ended the visit too, or the span is not on one timeline.
    private func exitContext(
        for visit: GeofenceDwellVisit,
        geofence: Geofence,
        exit: GeofenceExitMark,
        processedAt reading: GeofenceClockReading,
        source: String
    ) -> GeofenceExitContext? {
        guard visit.entryObserved, !visit.awaitsPresenceProof, geofence.transitionTypes.contains(.exit),
              !outsideEvidenceOvertook(visit, geofenceId: geofence.id),
              Self.spanIsTimeable(visit, exitedAt: exit.date, processedAt: reading)
        else { return nil }
        return GeofenceExitContext(
            visitId: visit.visitId,
            enteredAt: visit.enteredAt,
            durationSeconds: Self.reportedSeconds(from: visit.enteredAt, to: exit.date),
            detectionSource: source
        )
    }

    /// Whether outside evidence this process holds ends `visit`: the SDK saw the device away, so
    /// the stay may span an excursion the OS missed. Normally that evidence has already removed
    /// the visit; this covers an EXIT that read it before the removal landed.
    private func outsideEvidenceOvertook(_ visit: GeofenceDwellVisit, geofenceId: String) -> Bool {
        exitMarks[geofenceId]?.contains { $0.source == .outsideEvidence && $0.overtakes(visit) } ?? false
    }

    /// Whether the wall-clock span from `visit`'s entry to `exitedAt` is the time the visit lasted:
    /// the wall clock kept step with uptime from the visit's recording to the EXIT's processing
    /// (`GeofenceVisitElapsed.wallClockAgrees`), and neither date is ahead of the clock it was
    /// processed on. Only a clock since set back dates an event ahead, and then the date is on
    /// another timeline, its uptime only clamped to processing.
    private static func spanIsTimeable(
        _ visit: GeofenceDwellVisit,
        exitedAt: Date,
        processedAt reading: GeofenceClockReading
    ) -> Bool {
        guard let timing = visit.timing,
              timing.elapsed(enteredAt: visit.enteredAt, until: exitedAt, at: reading)?.wallClockAgrees == true
        else { return false }
        let tolerance = GeofenceConstants.dwellWallClockStepTolerance
        let recordedWall = timing.wallOffset + timing.recordedUptime
        return visit.enteredAt.timeIntervalSince1970 - recordedWall <= tolerance
            && exitedAt.timeIntervalSince(reading.wall) <= tolerance
    }

    /// The duration an EXIT reports: the difference of the two whole epoch seconds, so it equals
    /// the event's whole-second timestamp minus the `enteredAt` it carries, which is serialized by
    /// truncation too. Can be a second more than `wholeSeconds` (100.9 s → 160.1 s reports 60, not
    /// 59); qualifying stays on `wholeSeconds`, the elapsed time actually observed.
    static func reportedSeconds(from start: Date, to end: Date) -> Int {
        max(0, Int(end.timeIntervalSince1970) - Int(start.timeIntervalSince1970))
    }

    /// Remembers `visit`, which a re-ENTER replaced because an EXIT overtook it, under the exact
    /// dates of the EXIT events that did: one of them may still be in flight to report it. Not
    /// when outside evidence overtook it too, which no EXIT may time across, nor when only outside
    /// evidence did, which no EXIT event will come to claim. With `reenteredAt`, only EXITs that
    /// ENTER followed count.
    func rememberVisitEndedByPendingExit(
        _ visit: GeofenceDwellVisit,
        geofenceId: String,
        reenteredAt reentry: GeofenceExitMark? = nil
    ) {
        let overtaking = (exitMarks[geofenceId] ?? []).filter { $0.overtakes(visit) }
        let exitDates = Set(overtaking.filter { exit in
            exit.source == .exitEvent && (reentry.map { Self.enter($0, follows: exit) } ?? true)
        }.map(\.date))
        guard !exitDates.isEmpty, !overtaking.contains(where: { $0.source == .outsideEvidence }) else { return }
        visitsEndedByPendingExit[geofenceId] = (visit, exitDates)
    }

    /// `currentVisit` is removing `visit` because a later native ENTER superseded it. When an EXIT
    /// already seen ended it before that ENTER, the ENTER is the re-entry after it, not a crossing
    /// that shows the EXIT was lost: the visit is remembered for that EXIT, which may still be in
    /// flight. Any other break in its continuity leaves nothing to report.
    func rememberIfReenteredAfterItsExit(_ visit: GeofenceDwellVisit, geofenceId: String) {
        guard let reentry = enterMarks[geofenceId], reentry.supersedes(visit),
              continuityHolds(for: visit, geofenceId: geofenceId, ignoringLaterEnter: true)
        else { return }
        rememberVisitEndedByPendingExit(visit, geofenceId: geofenceId, reenteredAt: reentry)
    }

    /// Whether `enter` came after `exit`, on one wall-clock timeline. Across a step neither date
    /// orders against the other, so it did not, as far as anything here can tell.
    private static func enter(_ enter: GeofenceExitMark, follows exit: GeofenceExitMark) -> Bool {
        abs(enter.wallOffset - exit.wallOffset) <= GeofenceConstants.dwellWallClockStepTolerance
            && enter.mappedUptime >= exit.mappedUptime
    }

    /// Takes the visit an overlapping re-ENTER replaced for exactly this EXIT — one of the EXIT
    /// events remembered with it, by its original date — if it still belongs to `userId` and the
    /// fence's geometry, and its continuity still holds. Consumed, so no other EXIT can report it,
    /// and left for its own EXIT by any other, however close in time.
    private func takeVisitEndedByPendingExit(
        geofence: Geofence,
        exit: GeofenceExitMark,
        userId: String
    ) -> GeofenceDwellVisit? {
        guard let ended = visitsEndedByPendingExit[geofence.id], ended.exitDates.contains(exit.date) else { return nil }
        visitsEndedByPendingExit.removeValue(forKey: geofence.id)
        guard ended.visit.userId == userId,
              ended.visit.geometryRevision == geofence.dwellRevision,
              exit.overtakes(ended.visit),
              // Judged up to this EXIT: the re-entry that replaced it is a later stay.
              continuityHolds(for: ended.visit, geofenceId: geofence.id, ignoringLaterEnter: true)
        else { return nil }
        return ended.visit
    }
}
