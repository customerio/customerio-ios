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

    /// Removes the stored visit only when it is stale against what is stored NOW: another user's,
    /// or recorded against geometry the cached fence no longer has. A caller holding an older
    /// snapshot of the fence must not delete a visit recorded against the newer geometry.
    func removeDwellVisitIfStale(geofenceId: String, currentUserId: String) {
        var state = loadFromDisk() ?? GeofenceState()
        guard let stored = state.dwellVisits?[geofenceId] else { return }
        let retained = Self.dwellVisits(
            [geofenceId: stored], retainedFor: state.cachedGeofences ?? []
        )?[geofenceId] != nil
        guard stored.userId != currentUserId || !retained else { return }
        state.dwellVisits?.removeValue(forKey: geofenceId)
        saveToDisk(state)
    }

    func clearDwellVisits() {
        var state = loadFromDisk() ?? GeofenceState()
        guard state.dwellVisits != nil else { return }
        state.dwellVisits = nil
        saveToDisk(state)
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
