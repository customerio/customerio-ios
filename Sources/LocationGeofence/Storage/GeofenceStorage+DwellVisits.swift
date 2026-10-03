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
              geofence.dwellThresholdSeconds > 0
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
    }

    /// Compare-and-set with the same guards as `markDwellVisitEmitted`: stores `proposed` on `visit`
    /// only while it is still the stored, un-emitted visit for this fence and holds no reservation.
    func reserveDwellEmission(
        _ proposed: GeofenceDwellReservation,
        for visit: GeofenceDwellVisit,
        geofenceId: String
    ) -> DwellReservationResult {
        var state = loadFromDisk() ?? GeofenceState()
        guard var stored = state.dwellVisits?[geofenceId],
              stored.visitId == visit.visitId,
              stored.userId == visit.userId,
              stored.geometryRevision == visit.geometryRevision,
              state.cachedGeofences?.first(where: { $0.id == geofenceId })?.dwellRevision == visit.geometryRevision,
              !stored.emitted
        else { return .superseded }
        if let existing = stored.dwellReservation { return .reserved(existing) }
        // A visit an observed boundary closed qualifies no first dwell: it would span the departure.
        guard stored.closedByObservedBoundary == nil else { return .superseded }
        stored.dwellReservation = proposed
        state.dwellVisits?[geofenceId] = stored
        return saveToDisk(state) ? .reserved(proposed) : .writeFailed
    }

    func removeDwellVisit(geofenceId: String) {
        var state = loadFromDisk() ?? GeofenceState()
        guard state.dwellVisits?.removeValue(forKey: geofenceId) != nil else { return }
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
    /// - Returns: the removed visit id per fence.
    @discardableResult
    func removeDwellVisits(geofenceId: String?, spanning loss: GeofenceClockReading) -> [String: String] {
        removeDwellVisits { id, visit in
            (geofenceId == nil || id == geofenceId) && (visit.timing?.spans(loss) ?? true)
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
            return geofence.dwellThresholdSeconds > 0 && geofence.dwellRevision == visit.geometryRevision
        }
    }
}
