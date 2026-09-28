import CioInternalCommon
import Foundation

/// The duration an EXIT carries, split from the coordinator's visit lifecycle so both stay under
/// the file cap. `internal` rather than `private` only because of this split.
extension GeofenceDwellCoordinator {
    /// What an EXIT does to the visit. `endedVisitId` is the visit it read and ends; nil when it
    /// found none, or found one it must leave — a visit that began after this EXIT.
    func exitContext(
        geofence: Geofence,
        exitedAt: Date,
        detectionSource: String,
        expectedUserId: String?
    ) async -> (context: GeofenceExitContext?, endedVisitId: String?) {
        guard let userId = contextStore.currentUserId, !userId.isEmpty,
              expectedUserId == nil || expectedUserId == userId
        else { return (nil, nil) }
        let stored = await currentVisit(geofence: geofence, userId: userId)
        let endedByThisExit = takeVisitEndedByPendingExit(geofence: geofence, exitedAt: exitedAt, userId: userId)
        // A delayed exit from an older visit must not clear a newer visit.
        if let stored, exitedAt >= stored.enteredAt {
            return (exitContext(for: stored, geofence: geofence, exitedAt: exitedAt, source: detectionSource), stored.visitId)
        }
        // The visit this EXIT ends was already replaced by an overlapping re-entry; there is nothing
        // left to remove, but its duration still travels with the EXIT.
        return (
            endedByThisExit.flatMap { exitContext(for: $0, geofence: geofence, exitedAt: exitedAt, source: detectionSource) },
            nil
        )
    }

    /// The duration an EXIT carries for `visit`; nil when the visit's start was not an observed
    /// entry, or the customer did not configure EXIT.
    private func exitContext(
        for visit: GeofenceDwellVisit,
        geofence: Geofence,
        exitedAt: Date,
        source: String
    ) -> GeofenceExitContext? {
        guard visit.entryObserved, geofence.transitionTypes.contains(.exit) else { return nil }
        return GeofenceExitContext(
            visitId: visit.visitId,
            enteredAt: visit.enteredAt,
            durationSeconds: Self.reportedSeconds(from: visit.enteredAt, to: exitedAt),
            detectionSource: source
        )
    }

    /// The duration an EXIT reports: the difference of the two whole epoch seconds, so it equals
    /// the event's whole-second timestamp minus the `enteredAt` it carries, which is serialized by
    /// truncation too. Can be a second more than `wholeSeconds` (100.9 s → 160.1 s reports 60, not
    /// 59); qualifying stays on `wholeSeconds`, the elapsed time actually observed.
    static func reportedSeconds(from start: Date, to end: Date) -> Int {
        max(0, Int(end.timeIntervalSince1970) - Int(start.timeIntervalSince1970))
    }

    /// Takes the visit an overlapping re-ENTER replaced for exactly this EXIT, if it still belongs
    /// to `userId` and the fence's geometry. Consumed, so no other EXIT can report it.
    private func takeVisitEndedByPendingExit(
        geofence: Geofence,
        exitedAt: Date,
        userId: String
    ) -> GeofenceDwellVisit? {
        guard let ended = visitsEndedByPendingExit[geofence.id], ended.exitedAt == exitedAt else { return nil }
        visitsEndedByPendingExit.removeValue(forKey: geofence.id)
        guard ended.visit.userId == userId,
              ended.visit.geometryRevision == geofence.dwellRevision,
              ended.visit.enteredAt <= exitedAt
        else { return nil }
        return ended.visit
    }
}
