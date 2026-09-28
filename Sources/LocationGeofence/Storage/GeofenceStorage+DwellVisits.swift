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
        var state = loadFromDisk() ?? GeofenceState()
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
