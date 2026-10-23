import CioInternalCommon
import Foundation

/// Durable dwell visits, split out to keep `GeofenceStorage` readable. Methods are `internal`
/// (not `private`) only because they live in a separate file from their state; each still runs its
/// load → modify → save inside the actor with no `await` between steps.
extension GeofenceStorage {
    func getDwellVisit(geofenceId: String) -> GeofenceDwellVisit? {
        loadFromDisk()?.dwellVisits?[geofenceId]
    }

    @discardableResult
    func saveDwellVisit(_ visit: GeofenceDwellVisit, geofenceId: String) -> Bool {
        saveDwellVisit(visit, geofenceId: geofenceId, onlyIfStored: nil, requiresMatch: false)
    }

    /// Compare-and-set: writes `visit` only while the store holds no visit for the fence, or still
    /// holds `expectedVisitId` — the one the caller read. A visit written by an overlapping callback
    /// since that read is never overwritten.
    func saveDwellVisit(_ visit: GeofenceDwellVisit, geofenceId: String, replacing expectedVisitId: String?) -> Bool {
        saveDwellVisit(visit, geofenceId: geofenceId, onlyIfStored: expectedVisitId, requiresMatch: true)
    }

    private func saveDwellVisit(
        _ visit: GeofenceDwellVisit,
        geofenceId: String,
        onlyIfStored expectedVisitId: String?,
        requiresMatch: Bool
    ) -> Bool {
        var state = loadFromDisk() ?? GeofenceState()
        if requiresMatch, let stored = state.dwellVisits?[geofenceId], stored.visitId != expectedVisitId {
            return false
        }
        guard let geofence = state.cachedGeofences?.first(where: { $0.id == geofenceId }),
              geofence.dwellRevision == visit.geometryRevision,
              geofence.dwellThresholdSeconds > 0 || geofence.transitionTypes.contains(.exit)
        else { return false }
        var visits = state.dwellVisits ?? [:]
        visits[geofenceId] = visit
        state.dwellVisits = visits
        return saveToDisk(state)
    }

    /// Outcome of recording that a visit's dwell was persisted for delivery.
    enum DwellEmissionMark: Equatable {
        case marked
        /// The visit ended, was replaced, or no longer matches its user or geometry. Nothing was
        /// written: the delivered dwell described that visit, not whatever is stored now.
        case superseded
        case writeFailed
    }

    /// Compare-and-set: marks `visit` emitted only while it is still the stored visit for this
    /// fence with the same id, user, and geometry revision, and that revision is still current.
    func markDwellVisitEmitted(_ visit: GeofenceDwellVisit, geofenceId: String) -> DwellEmissionMark {
        var state = loadFromDisk() ?? GeofenceState()
        guard var stored = state.dwellVisits?[geofenceId],
              stored.visitId == visit.visitId,
              stored.userId == visit.userId,
              stored.geometryRevision == visit.geometryRevision,
              state.cachedGeofences?.first(where: { $0.id == geofenceId })?.dwellRevision == visit.geometryRevision
        else { return .superseded }
        guard !stored.emitted else { return .marked }
        stored.emitted = true
        state.dwellVisits?[geofenceId] = stored
        return saveToDisk(state) ? .marked : .writeFailed
    }

    /// Outcome of fixing a visit's dwell before it is delivered.
    enum DwellReservationResult: Equatable {
        /// The reservation the dwell must be delivered with: `proposed`, or the one an earlier
        /// attempt already stored, which always wins.
        case reserved(GeofenceDwellReservation)
        /// The visit ended, was replaced, no longer matches its user or geometry, or its dwell was
        /// already marked emitted. Nothing was written and nothing should be delivered.
        case superseded
        case writeFailed
        /// Written as the visit's staged reservation: no fact yet, until it is admitted.
        case staged(GeofenceDwellReservation)
        /// Not admitted: the polygon was left since the visit began, by evidence on disk. The
        /// staged reservation is taken back.
        case departed
    }

    /// Stages and admits `proposed` in one go, for a caller that has already decided the admission.
    func reserveDwellEmission(
        _ proposed: GeofenceDwellReservation,
        for visit: GeofenceDwellVisit,
        geofenceId: String
    ) async -> DwellReservationResult {
        let result = await stageDwellReservation(proposed, for: visit, geofenceId: geofenceId)
        guard case .staged(let staged) = result else { return result }
        return await admitStagedDwellReservation(staged, for: visit, geofenceId: geofenceId)
    }

    /// Compare-and-set with the same guards as `markDwellVisitEmitted`: stages `proposed` on `visit`
    /// (`GeofenceDwellVisit.stagedDwellReservation`, replacing any staged before) only while it is
    /// still the stored, un-emitted visit for this fence and holds no reservation. One it already
    /// holds is returned as `.reserved`: it always wins.
    func stageDwellReservation(
        _ proposed: GeofenceDwellReservation,
        for visit: GeofenceDwellVisit,
        geofenceId: String
    ) async -> DwellReservationResult {
        await runBeforeReservationWrite()
        var state = loadFromDisk() ?? GeofenceState()
        guard var stored = Self.reservable(visit, geofenceId: geofenceId, in: state) else { return .superseded }
        if let existing = stored.dwellReservation { return .reserved(existing) }
        stored.stagedDwellReservation = proposed
        state.dwellVisits?[geofenceId] = stored
        return saveToDisk(state) ? .staged(proposed) : .writeFailed
    }

    /// Makes `staged` the visit's reservation, a fact from now on, once its admission stands: only
    /// while the visit still holds exactly that staged reservation under the same guards, and — in
    /// the same read — while no departure from its polygon is recorded since its entry. A departure
    /// recorded while the reservation was being staged may precede the qualifying fix; promoted, the
    /// reservation would be delivered by every retry, EXIT and orphan sweep after.
    func admitStagedDwellReservation(
        _ staged: GeofenceDwellReservation,
        for visit: GeofenceDwellVisit,
        geofenceId: String
    ) async -> DwellReservationResult {
        await runBeforeAdmission()
        var state = loadFromDisk() ?? GeofenceState()
        guard var stored = Self.reservable(visit, geofenceId: geofenceId, in: state) else { return .superseded }
        if let existing = stored.dwellReservation { return .reserved(existing) }
        guard stored.stagedDwellReservation == staged else { return .superseded }
        guard !Self.polygonLeft(since: stored, geofenceId: geofenceId, in: state) else {
            stored.stagedDwellReservation = nil
            state.dwellVisits?[geofenceId] = stored
            saveToDisk(state)
            return .departed
        }
        stored.dwellReservation = staged
        stored.stagedDwellReservation = nil
        state.dwellVisits?[geofenceId] = stored
        return saveToDisk(state) ? .reserved(staged) : .writeFailed
    }

    /// The stored visit a reservation may be written on: still `visit`, its user and geometry, not
    /// emitted, and not closed by an observed boundary — such a visit qualifies no first dwell, as
    /// it would span the departure — unless it already holds a reservation.
    private static func reservable(_ visit: GeofenceDwellVisit, geofenceId: String, in state: GeofenceState) -> GeofenceDwellVisit? {
        guard let stored = state.dwellVisits?[geofenceId],
              stored.visitId == visit.visitId,
              stored.userId == visit.userId,
              stored.geometryRevision == visit.geometryRevision,
              state.cachedGeofences?.first(where: { $0.id == geofenceId })?.dwellRevision == visit.geometryRevision,
              !stored.emitted,
              stored.dwellReservation != nil || stored.closedByObservedBoundary == nil
        else { return nil }
        return stored
    }

    /// Persists what `visitId` has spent proving its dwell, as the coordinator counted it in memory:
    /// only while that is still the stored visit, and never lowering a count or moving the last
    /// request back, so writes landing out of order keep the most spent.
    /// - Returns: whether the store now holds at least `ledger`'s spending for that visit, or no
    ///   longer holds the visit at all; false when the write failed or the stored state could not
    ///   be read.
    @discardableResult
    func recordDwellProofLedger(geofenceId: String, visitId: String, ledger: GeofenceDwellProofLedger) -> Bool {
        // Unreadable is not absent: reporting the visit gone would confirm a charge never saved.
        guard var state = loadFromDisk() else { return stateIsAbsent() }
        guard var stored = state.dwellVisits?[geofenceId], stored.visitId == visitId else { return true }
        let merged = ledger.merged(with: stored)
        guard merged.attempts != stored.dwellProofAttempts || merged.checks != stored.dwellProofChecks
            || merged.refusedChecks != stored.dwellProofRefusedChecks || merged.lastRequest != stored.lastDwellProofRequest
        else { return true }
        guard !ledgerSaveFails else { return false }
        stored.dwellProofAttempts = merged.attempts
        stored.dwellProofChecks = merged.checks
        stored.dwellProofRefusedChecks = merged.refusedChecks
        stored.lastDwellProofRequest = merged.lastRequest
        state.dwellVisits?[geofenceId] = stored
        return saveToDisk(state)
    }

    /// Records that `visitId` was decisively proven inside at `provenAt`, keeping the latest; only
    /// while it is still the stored visit, so a stale copy cannot stamp a newer stay.
    func stampDecisiveInside(geofenceId: String, visitId: String, at provenAt: Date) {
        var state = loadFromDisk() ?? GeofenceState()
        guard var stored = state.dwellVisits?[geofenceId], stored.visitId == visitId,
              provenAt > (stored.lastDecisiveInsideAt ?? .distantPast)
        else { return }
        stored.lastDecisiveInsideAt = provenAt
        state.dwellVisits?[geofenceId] = stored
        saveToDisk(state)
    }

    /// Takes back a staged reservation an admission refused — only while the stored visit is still
    /// `visit` staging exactly `reservation` — so nothing of it is left on disk. Tidying only: a
    /// staged reservation is never a fact, so one left behind delivers nothing.
    /// - Returns: whether the staged reservation was removed.
    @discardableResult
    func retractDwellReservation(_ reservation: GeofenceDwellReservation, from visit: GeofenceDwellVisit, geofenceId: String) -> Bool {
        var state = loadFromDisk() ?? GeofenceState()
        guard var stored = state.dwellVisits?[geofenceId], stored.visitId == visit.visitId,
              stored.stagedDwellReservation == reservation
        else { return false }
        guard !retractionFailsForTesting else { return false }
        stored.stagedDwellReservation = nil
        state.dwellVisits?[geofenceId] = stored
        return saveToDisk(state)
    }

    func getOrphanedDwells() -> [GeofenceOrphanedDwell] {
        loadFromDisk()?.orphanedDwells ?? []
    }

    /// Forgets the orphaned dwell of `visitId`: delivered, refused for good, or given up.
    func removeOrphanedDwell(visitId: String) {
        guard var state = loadFromDisk(), let orphans = state.orphanedDwells,
              orphans.contains(where: { $0.visitId == visitId })
        else { return }
        let kept = orphans.filter { $0.visitId != visitId }
        state.orphanedDwells = kept.isEmpty ? nil : kept
        saveToDisk(state)
    }

    func removeDwellVisit(geofenceId: String) {
        var state = loadFromDisk() ?? GeofenceState()
        guard state.dwellVisits?.removeValue(forKey: geofenceId) != nil else { return }
        saveToDisk(state)
    }

    /// `removeDwellVisit(geofenceId:ifStill:)` for the visit an EXIT dated `endedAt` ends: in the
    /// same write, a reservation evidenced after that EXIT is dropped with the visit rather than
    /// kept as an orphan. It is no dwell of this stay — its fix may be a return's — so no path
    /// delivers it.
    func removeDwellVisit(geofenceId: String, ifStill visitId: String, endedAt: Date) {
        var state = loadFromDisk() ?? GeofenceState()
        guard let stored = state.dwellVisits?[geofenceId], stored.visitId == visitId else { return }
        if stored.dwellReservation?.isEvidenced(after: endedAt) == true {
            state.dwellVisits?[geofenceId]?.dwellReservation = nil
        }
        state.dwellVisits?.removeValue(forKey: geofenceId)
        saveToDisk(state)
    }

    /// Compare-and-remove: removes the stored visit only while it is still `visitId`, so a caller
    /// retracting the visit it wrote cannot delete one written since.
    func removeDwellVisit(geofenceId: String, ifStill visitId: String) {
        var state = loadFromDisk() ?? GeofenceState()
        guard state.dwellVisits?[geofenceId]?.visitId == visitId else { return }
        state.dwellVisits?.removeValue(forKey: geofenceId)
        saveToDisk(state)
    }

    /// Removes a polygon visit a pass found left behind outside — only while the stored belief is
    /// still outside and the outside fix `outside` overtakes the visit on the monotonic timeline
    /// (`GeofenceExitMark.overtakes`), both judged here, in the one write. A visit begun after that
    /// fix was written by a newer inside pass and is a stay of its own; a wall clock stepped back
    /// behind the visit's entry cannot keep it, as the mark orders by processing then.
    /// - Returns: the removed visit's id, nil when nothing was removed.
    func removeDwellVisitLeftOutside(geofenceId: String, endedBy outside: GeofenceExitMark) -> String? {
        var state = loadFromDisk() ?? GeofenceState()
        guard state.polygonMembership?[geofenceId]?.membership == .outside,
              let visit = state.dwellVisits?[geofenceId], outside.overtakes(visit)
        else { return nil }
        state.dwellVisits?.removeValue(forKey: geofenceId)
        return saveToDisk(state) ? visit.visitId : nil
    }

    func getClockReference() -> GeofenceClockReading? {
        loadFromDisk()?.clockReference
    }

    func setClockReference(_ reading: GeofenceClockReading) {
        var state = loadFromDisk() ?? GeofenceState()
        state.clockReference = reading
        saveToDisk(state)
    }

    /// Removes the captured visit only when it is stale against what is stored NOW: another user's,
    /// or recorded against geometry the cached fence no longer has. A caller holding an older
    /// snapshot of the fence or user must not delete a visit written after its read.
    func removeDwellVisitIfStale(geofenceId: String, currentUserId: String, ifStill visitId: String) {
        var state = loadFromDisk() ?? GeofenceState()
        guard let stored = state.dwellVisits?[geofenceId], stored.visitId == visitId else { return }
        let retained = Self.dwellVisits(
            [geofenceId: stored], retainedFor: state.cachedGeofences ?? []
        )?[geofenceId] != nil
        guard stored.userId != currentUserId || !retained else { return }
        state.dwellVisits?.removeValue(forKey: geofenceId)
        saveToDisk(state)
    }

    /// Removes the visits — of one fence, or (nil) every fence — whose continuity spans `loss`:
    /// entered no later than it, recorded on another boot, or recorded with no timing at all. A
    /// visit entered after the loss was seen is not one it interrupted, however late this runs.
    /// One that still owes its reserved dwell is kept: the reservation is a fact about the stay
    /// before the loss (`GeofenceDwellVisit.owesDwell`).
    /// - Returns: the removed visit id per fence.
    @discardableResult
    func removeDwellVisits(geofenceId: String?, spanning loss: GeofenceClockReading) -> [String: String] {
        removeDwellVisits { id, visit in
            (geofenceId == nil || id == geofenceId) && !visit.owesDwell && (visit.timing?.spans(loss) ?? true)
        }
    }

    /// Removes every visit `matching` selects, in one write.
    /// - Returns: the removed visit id per fence.
    @discardableResult
    func removeDwellVisits(matching: (String, GeofenceDwellVisit) -> Bool) -> [String: String] {
        var state = loadFromDisk() ?? GeofenceState()
        guard let visits = state.dwellVisits else { return [:] }
        let removed = visits.filter { matching($0.key, $0.value) }
        guard !removed.isEmpty else { return [:] }
        state.dwellVisits = visits.filter { removed[$0.key] == nil }
        saveToDisk(state)
        return removed.mapValues(\.visitId)
    }

    /// The stored visits that still describe a cached fence: one that still tracks a visit and has
    /// the geometry revision the visit was recorded against. Anything else is dropped.
    ///
    /// Nothing upstream dedupes fence ids, so a payload listing one twice reaches here. The first
    /// occurrence decides, matching every `first(where:)` lookup that reads the same cache.
    static func dwellVisits(
        _ visits: [String: GeofenceDwellVisit]?,
        retainedFor geofences: [Geofence]
    ) -> [String: GeofenceDwellVisit]? {
        let current = Dictionary(geofences.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return visits?.filter { id, visit in
            guard let geofence = current[id] else { return false }
            return (geofence.dwellThresholdSeconds > 0 || geofence.transitionTypes.contains(.exit)) &&
                geofence.dwellRevision == visit.geometryRevision
        }
    }
}
