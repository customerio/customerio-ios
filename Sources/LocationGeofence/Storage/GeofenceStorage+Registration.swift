import CioInternalCommon
import Foundation

/// The registration centre and its registered set, split out of `GeofenceStorage.swift`.
extension GeofenceStorage {
    /// Centre of the most recent registration. The sync decision measures from here to detect a
    /// stale ranking.
    func getLastRegistrationCenter() -> LocationData? {
        loadFromDisk()?.movementTriggerCenter
    }

    /// Business geofence IDs the OS accepted at the last registration.
    func getRegisteredBusinessIds() -> Set<String> {
        loadFromDisk()?.monitoredGeofenceIds ?? []
    }

    /// Records the registration centre and business IDs in one load-modify-save. Distinct from
    /// `recordSync` (the fetch anchor), which a local re-rank leaves intact.
    func recordRegistration(center: LocationData, businessIds: Set<String>) {
        var state = loadFromDisk() ?? GeofenceState()
        state.movementTriggerCenter = center
        state.monitoredGeofenceIds = businessIds
        // Drop baselines for evicted regions. Unmonitored, a stale `.enter` baseline is never
        // balanced, and a later re-register with the same circle would keep it, so the next real
        // arrival reads as no change. Also bounds the records to the registered set.
        if let records = state.monitorRegionRecords {
            let retained = businessIds.union([GeofenceConstants.movementTriggerIdentifier])
            state.monitorRegionRecords = records.filter { retained.contains($0.key) }
        }
        state.prunePolygonState(retaining: businessIds)
        saveToDisk(state)
    }
}
