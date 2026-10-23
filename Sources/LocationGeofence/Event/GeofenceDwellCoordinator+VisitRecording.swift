import Foundation

/// Recording new visits, from an ENTER or from inside evidence, split from the coordinator's
/// boundary handling so both stay under the file cap. One file, so its helpers stay private.
extension GeofenceDwellCoordinator {
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
        continuingVisitId: String? = nil,
        qualifiesDwell: Bool = true
    ) async {
        await syncClockReference(readClock())
        guard tracksVisit(geofence),
              let userId = contextStore.currentUserId, !userId.isEmpty,
              expectedUserId == nil || expectedUserId == userId,
              let visit = await visitForEvidence(
                  geofence: geofence, observedAt: observedAt, userId: userId,
                  beginsNewVisit: beginsNewVisit, continuingVisitId: continuingVisitId
              )
        else { return }
        // The bookkeeping above still runs, so a marginal arrival starts, proves or continues its
        // visit at this time. Only a fix whose accuracy disk lies wholly inside proves the stay; a
        // reservation proven earlier still repeats its delivery.
        if qualifiesDwell {
            // Kept on the visit for the EXIT: how recently the device was known inside bounds how
            // early it could have left, when the OS does not date the departure.
            await storage.stampDecisiveInside(geofenceId: geofence.id, visitId: visit.visitId, at: observedAt)
        }
        guard qualifiesDwell || visit.dwellReservation != nil else { return }
        await emitDwellIfQualified(
            geofence: geofence, visit: visit, observedAt: observedAt, source: source, userId: userId
        )
    }

    /// The visit inside evidence applies to: the stored one, or a new one when there is none or
    /// the evidence is an observed entry no older than it. Nil when the evidence must be dropped.
    private func visitForEvidence(
        geofence: Geofence,
        observedAt: Date,
        userId: String,
        beginsNewVisit: Bool,
        continuingVisitId: String?
    ) async -> GeofenceDwellVisit? {
        // Placed on the monotonic timeline before the first await, as it is processed.
        let observedUptime = GeofenceVisitTiming.uptime(of: observedAt, at: readClock())
        let stored = await currentVisit(geofence: geofence, userId: userId)
        if let continuingVisitId, stored?.visitId != continuingVisitId { return nil }
        // The first fresh inside proof for a candidate discovered from the anchor: the candidate
        // re-starts here, as a stay this evidence opens, so none of the time before it counts.
        if let stored, !stored.awaitsPresenceProof,
           !beginsNewVisit || (stored.timing?.entryUptime(orderedAt: readClock()) ?? .infinity) > observedUptime {
            return stored
        }
        guard let visit = makeVisit(
            geofence: geofence, enteredAt: observedAt, userId: userId,
            entryObserved: beginsNewVisit && stored?.awaitsPresenceProof != true
        ) else { return nil }
        guard await saveNewVisit(visit, geofenceId: geofence.id, replacing: stored?.visitId) else { return nil }
        scheduleDeadline(for: geofence, visit: visit)
        return visit
    }

    /// Internal for `handleBoundary`.
    func startVisitIfNeeded(
        geofence: Geofence,
        enteredAt: Date,
        expectedUserId: String?,
        entryObserved: Bool,
        presenceProven: Bool
    ) async {
        // A snapshot that tracks no visit removes none: it may predate the refresh that enabled
        // the dwell, and a fence that really stopped tracking had its visit pruned with the cache.
        guard tracksVisit(geofence),
              let userId = contextStore.currentUserId, !userId.isEmpty,
              expectedUserId == nil || expectedUserId == userId
        else { return }
        // A visit a later native ENTER supersedes is gone by now (`continuityHolds`): an ENTER that
        // is a crossing starts a stay of its own.
        let existing = await currentVisit(geofence: geofence, userId: userId)
        // A copy of the ENTER that started a visit keeps it. One an EXIT has already been seen
        // ending does not count: that EXIT may still be suspended before its removal, and adopting
        // the visit would leave this re-entry with none once it lands. Nor does a candidate awaiting
        // proof, when this ENTER is proof.
        if let existing, !exitOvertook(existing, geofenceId: geofence.id), existing.closedByObservedBoundary == nil,
           !(presenceProven && existing.awaitsPresenceProof) {
            scheduleDeadline(for: geofence, visit: existing)
            return
        }
        guard let visit = makeVisit(
            geofence: geofence, enteredAt: enteredAt, userId: userId,
            entryObserved: entryObserved, awaitsPresenceProof: !presenceProven
        ) else { return }
        if contextStore.currentUserId == userId,
           await saveNewVisit(visit, geofenceId: geofence.id, replacing: existing?.visitId) {
            if let existing { rememberVisitEndedByPendingExit(existing, geofenceId: geofence.id) }
            scheduleDeadline(for: geofence, visit: visit)
        }
    }

    /// Writes a new visit unless an EXIT or a loss of continuity for the fence overtook it. Checked
    /// before the write and again after it: an EXIT or a loss's removal landing during the write may
    /// have read the store before it did, and then nothing else would close the visit. The
    /// retraction is compare-and-remove, so it cannot take out a visit written since.
    ///
    /// `replacing` is the visit the caller read, nil for none; the write is refused if an
    /// overlapping callback has stored a different one since.
    private func saveNewVisit(_ visit: GeofenceDwellVisit, geofenceId: String, replacing: String?) async -> Bool {
        guard !isOvertaken(visit, geofenceId: geofenceId),
              await storage.saveDwellVisit(visit, geofenceId: geofenceId, replacing: replacing)
        else { return false }
        guard !isOvertaken(visit, geofenceId: geofenceId) else {
            await storage.removeDwellVisit(geofenceId: geofenceId, ifStill: visit.visitId)
            return false
        }
        return true
    }

    private func isOvertaken(_ visit: GeofenceDwellVisit, geofenceId: String) -> Bool {
        // An old ENTER dated before a backward clock step may arrive after an EXIT dated on
        // the new clock. Neither its date nor its later receipt proves re-entry. Fresh inside
        // evidence can start another candidate on the current clock instead.
        if let timing = visit.timing,
           visit.enteredAt.timeIntervalSince1970 > timing.wallOffset + timing.recordedUptime + GeofenceConstants.dwellWallClockStepTolerance,
           exitMarks[geofenceId]?.isEmpty == false {
            return true
        }
        return exitOvertook(visit, geofenceId: geofenceId) || lossOvertook(visit, geofenceId: geofenceId)
    }

    /// A new visit, stamped with the timeline, access and identity it is recorded under. Nil when
    /// the identity in force is no longer `userId`, which the caller read before an await.
    private func makeVisit(
        geofence: Geofence,
        enteredAt: Date,
        userId: String,
        entryObserved: Bool,
        awaitsPresenceProof: Bool = false
    ) -> GeofenceDwellVisit? {
        let identity = identityTracker.currentIdentity
        if let identity, identity.userId != userId { return nil }
        let visitId = UUID().uuidString
        visitsRecordedHere.insert(visitId)
        let reading = readClock()
        let timing = GeofenceVisitTiming(enteredAt: enteredAt, recordedAt: reading)
        return GeofenceDwellVisit(
            visitId: visitId,
            enteredAt: enteredAt,
            geometryRevision: geofence.dwellRevision,
            userId: userId,
            emitted: false,
            // An entry dated on a clock that has since stepped still starts the visit, but is not
            // reported, nor any duration from it.
            entryObserved: entryObserved && entryIsOnCurrentClock(timing, enteredAt: enteredAt, reading: reading),
            timing: timing,
            locationAccess: currentLocationAccess(),
            awaitsPresenceProof: awaitsPresenceProof,
            identityVersion: identity?.version,
            identityLineage: identity?.lineage
        )
    }
}
