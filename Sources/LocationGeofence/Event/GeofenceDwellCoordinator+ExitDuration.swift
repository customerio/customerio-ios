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
    /// evidence or an ENTER this EXIT already knew of ended the visit, or the span is not on one
    /// timeline.
    private func exitContext(
        for visit: GeofenceDwellVisit,
        geofence: Geofence,
        exit: GeofenceExitMark,
        processedAt reading: GeofenceClockReading,
        source: String
    ) -> GeofenceExitContext? {
        guard visit.entryObserved, !visit.awaitsPresenceProof, geofence.transitionTypes.contains(.exit),
              !outsideEvidenceOvertook(visit, geofenceId: geofence.id),
              !enterKnownAtExitEnded(visit, exit: exit, geofenceId: geofence.id),
              Self.spanIsTimeable(visit, exitedAt: exit.date, processedAt: reading)
        else { return nil }
        return GeofenceExitContext(
            visitId: visit.visitId,
            enteredAt: visit.enteredAt,
            durationSeconds: Self.reportedSeconds(from: visit.enteredAt, to: exit.date),
            detectionSource: source
        )
    }

    /// Notes an EXIT in the OS callback, in OS order, before its routing task records it: the
    /// native ENTERs noted so far are what the EXIT knew of the stay's end (`keepEntersKnown`). A
    /// burst — ENTER, EXIT, ENTER — reaches the binder before any routing task runs, so by the time
    /// the EXIT is recorded a later ENTER may already have replaced an earlier one in its slot.
    func noteExitCallback(geofenceId: String, occurredAt: Date) {
        exitDuration.latestExitCallback[geofenceId] = occurredAt
        keepEntersKnown(at: occurredAt, geofenceId: geofenceId)
    }

    /// Records an EXIT event, and what it knew of the stay's end if its callback did not note it:
    /// an EXIT from a direct caller, or a polygon verdict dated by its fix.
    func recordExitEvent(_ exit: GeofenceExitMark, geofenceId: String) {
        recordExit(exit, geofenceId: geofenceId)
        keepEntersKnown(at: exit.date, geofenceId: geofenceId)
    }

    /// Keeps, on an EXIT's first note by its exact date, the native ENTERs then noted for its fence,
    /// which no later callback can erase by replacing an ENTER in its slot; a copy of the same EXIT
    /// keeps the first. Each record lives only while its EXIT's mark does (`exitMarks`, pruned as
    /// marks are subsumed), a visit is remembered for it, or it is the fence's latest EXIT callback,
    /// whose routing may still be on its way.
    private func keepEntersKnown(at date: Date, geofenceId: String) {
        var known = exitDuration.entersKnownAtExit[geofenceId] ?? [:]
        if known[date] == nil { known[date] = enterMarks[geofenceId] ?? GeofenceEnterMarks() }
        var live = Set((exitMarks[geofenceId] ?? []).filter { $0.source == .exitEvent }.map(\.date))
            .union(exitDuration.visitsEndedByPendingExit[geofenceId]?.exitDates ?? [])
        if let callback = exitDuration.latestExitCallback[geofenceId] { live.insert(callback) }
        exitDuration.entersKnownAtExit[geofenceId] = known.filter { live.contains($0.key) }
    }

    /// Whether an ENTER noted by the time this EXIT was first noted ended `visit` before the EXIT
    /// (`GeofenceEnterMarks.superseding`: a crossing, or a correction of a stay not yet qualified):
    /// the stay then ended at an EXIT the SDK missed, and this one is not its end. An ENTER after
    /// this EXIT is the re-entry and does not count; across a wall-clock step nothing orders the
    /// two, so it does.
    private func enterKnownAtExitEnded(_ visit: GeofenceDwellVisit, exit: GeofenceExitMark, geofenceId: String) -> Bool {
        let known = exitDuration.entersKnownAtExit[geofenceId]?[exit.date]
        return known?.superseding(visit).contains { !Self.enter($0, follows: exit) } ?? false
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
    /// evidence did, which no EXIT event will come to claim. With `reenteredAfter`, only EXITs that
    /// every one of those ENTERs followed count.
    func rememberVisitEndedByPendingExit(
        _ visit: GeofenceDwellVisit,
        geofenceId: String,
        reenteredAfter reentries: [GeofenceExitMark] = []
    ) {
        let overtaking = (exitMarks[geofenceId] ?? []).filter { $0.overtakes(visit) }
        let exitDates = Set(overtaking.filter { exit in
            exit.source == .exitEvent && reentries.allSatisfy { Self.enter($0, follows: exit) }
        }.map(\.date))
        guard !exitDates.isEmpty, !overtaking.contains(where: { $0.source == .outsideEvidence }) else { return }
        exitDuration.visitsEndedByPendingExit[geofenceId] = (visit, exitDates)
    }

    /// `currentVisit` is removing `visit` because later native ENTERs superseded it — a crossing,
    /// or a correction of a stay not yet qualified. When an EXIT already seen ended it before every
    /// one of those ENTERs, they are re-entries after it, not arrivals that show its EXIT was lost:
    /// the visit is remembered for that EXIT, which may still be in flight. One ENTER before the
    /// EXIT, of either kind, means the stay ended earlier unseen. Any other break in its continuity
    /// leaves nothing to report.
    func rememberIfReenteredAfterItsExit(_ visit: GeofenceDwellVisit, geofenceId: String) {
        guard let reentries = enterMarks[geofenceId]?.superseding(visit), !reentries.isEmpty,
              continuityHolds(for: visit, geofenceId: geofenceId, ignoringLaterEnter: true)
        else { return }
        rememberVisitEndedByPendingExit(visit, geofenceId: geofenceId, reenteredAfter: reentries)
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
        guard let ended = exitDuration.visitsEndedByPendingExit[geofence.id], ended.exitDates.contains(exit.date)
        else { return nil }
        exitDuration.visitsEndedByPendingExit.removeValue(forKey: geofence.id)
        guard ended.visit.userId == userId,
              ended.visit.geometryRevision == geofence.dwellRevision,
              exit.overtakes(ended.visit),
              // Judged up to this EXIT: the re-entry that replaced it is a later stay.
              continuityHolds(for: ended.visit, geofenceId: geofence.id, ignoringLaterEnter: true)
        else { return nil }
        return ended.visit
    }
}

/// What EXIT durations keep between callbacks, in memory, as `exitMarks` are.
struct GeofenceExitDurationState {
    /// A visit a re-ENTER replaced after an EXIT ended it, possibly before that EXIT read the store,
    /// under the exact dates of the EXIT events that ended it: that EXIT still reports its duration.
    var visitsEndedByPendingExit: [String: (visit: GeofenceDwellVisit, exitDates: Set<Date>)] = [:]
    /// Per fence and EXIT event date, the native ENTERs noted when that EXIT was first noted.
    var entersKnownAtExit: [String: [Date: GeofenceEnterMarks]] = [:]
    /// Per fence, the date of the latest EXIT its OS callback noted.
    var latestExitCallback: [String: Date] = [:]
}
