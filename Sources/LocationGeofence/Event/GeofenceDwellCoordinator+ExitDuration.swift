import CioInternalCommon
import Foundation

/// The duration an EXIT carries, split from the coordinator's visit lifecycle so both stay under
/// the file cap. `internal` rather than `private` only because of this split.
///
/// Ordering is on the monotonic timeline, like every other visit decision; a duration is only the
/// wall-clock span between two dates both on the visit's own, unbroken timeline.
extension GeofenceDwellCoordinator {
    /// What an EXIT does to the visit. `endedVisitId` is the visit it read and ends; nil when it
    /// found none, or found one it must leave — a visit that began after this EXIT. `reading` is
    /// the one the EXIT was placed on the monotonic timeline with, before any await.
    func exitContext(
        geofence: Geofence,
        exitedAt: Date,
        processedAt reading: GeofenceClockReading,
        detectionSource: String,
        expectedUserId: String?
    ) async -> (context: GeofenceExitContext?, endedVisitId: String?) {
        guard let userId = contextStore.currentUserId, !userId.isEmpty,
              expectedUserId == nil || expectedUserId == userId
        else { return (nil, nil) }
        let exitUptime = GeofenceVisitTiming.uptime(of: exitedAt, at: reading)
        let stored = await currentVisit(geofence: geofence, userId: userId)
        let endedByThisExit = takeVisitEndedByPendingExit(
            geofence: geofence, exitedAt: exitedAt, processedAt: reading, userId: userId
        )
        // A delayed exit from an older visit must not clear a newer visit.
        if let stored, Self.exit(exitedAt, atUptime: exitUptime, processedAt: reading, follows: stored) {
            return (
                exitContext(for: stored, geofence: geofence, exitedAt: exitedAt, processedAt: reading, source: detectionSource),
                stored.visitId
            )
        }
        // The visit this EXIT ends was already replaced by an overlapping re-entry; there is nothing
        // left to remove, but its duration still travels with the EXIT.
        return (
            endedByThisExit.flatMap {
                exitContext(for: $0, geofence: geofence, exitedAt: exitedAt, processedAt: reading, source: detectionSource)
            },
            nil
        )
    }

    /// The duration an EXIT carries for `visit`; nil when the visit's start was not an observed
    /// entry, the customer did not configure EXIT, or the span is not on one timeline.
    private func exitContext(
        for visit: GeofenceDwellVisit,
        geofence: Geofence,
        exitedAt: Date,
        processedAt reading: GeofenceClockReading,
        source: String
    ) -> GeofenceExitContext? {
        guard visit.entryObserved, geofence.transitionTypes.contains(.exit),
              Self.spanIsTimeable(visit, exitedAt: exitedAt, processedAt: reading)
        else { return nil }
        return GeofenceExitContext(
            visitId: visit.visitId,
            enteredAt: visit.enteredAt,
            durationSeconds: Self.reportedSeconds(from: visit.enteredAt, to: exitedAt),
            detectionSource: source
        )
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

    /// Whether an EXIT at `exitUptime` comes at or after `visit`'s entry. An EXIT dated ahead of
    /// the clock it was processed on has only a clamped uptime, which orders nothing; it was
    /// dated before a clock change, so it is placed on the visit's own timeline as well, where an
    /// EXIT from an earlier stay still reads as before the entry.
    private static func exit(
        _ exitedAt: Date,
        atUptime exitUptime: TimeInterval,
        processedAt reading: GeofenceClockReading,
        follows visit: GeofenceDwellVisit
    ) -> Bool {
        guard let timing = visit.timing, exitUptime >= timing.enteredUptime else { return false }
        guard exitedAt > reading.wall else { return true }
        return exitedAt.timeIntervalSince1970 - timing.wallOffset >= timing.enteredUptime
    }

    /// The duration an EXIT reports: the difference of the two whole epoch seconds, so it equals
    /// the event's whole-second timestamp minus the `enteredAt` it carries, which is serialized by
    /// truncation too. Can be a second more than `wholeSeconds` (100.9 s → 160.1 s reports 60, not
    /// 59); qualifying stays on `wholeSeconds`, the elapsed time actually observed.
    static func reportedSeconds(from start: Date, to end: Date) -> Int {
        max(0, Int(end.timeIntervalSince1970) - Int(start.timeIntervalSince1970))
    }

    /// Takes the visit an overlapping re-ENTER replaced for exactly this EXIT — the one recorded
    /// with its date — if it still belongs to `userId` and the fence's geometry, and its continuity
    /// still holds. Consumed, so no other EXIT can report it, and left for its own EXIT by any
    /// other, however close in time.
    private func takeVisitEndedByPendingExit(
        geofence: Geofence,
        exitedAt: Date,
        processedAt reading: GeofenceClockReading,
        userId: String
    ) -> GeofenceDwellVisit? {
        guard let ended = visitsEndedByPendingExit[geofence.id], ended.exitedAt == exitedAt else { return nil }
        visitsEndedByPendingExit.removeValue(forKey: geofence.id)
        let exitUptime = GeofenceVisitTiming.uptime(of: exitedAt, at: reading)
        guard ended.visit.userId == userId,
              ended.visit.geometryRevision == geofence.dwellRevision,
              Self.exit(exitedAt, atUptime: exitUptime, processedAt: reading, follows: ended.visit),
              continuityHolds(for: ended.visit, geofenceId: geofence.id)
        else { return nil }
        return ended.visit
    }
}
