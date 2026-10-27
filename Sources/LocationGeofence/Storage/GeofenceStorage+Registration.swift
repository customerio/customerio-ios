import CioInternalCommon
import Foundation

extension GeofenceStorage {
    func getLastRegistrationCenter() -> LocationData? {
        loadFromDisk()?.movementTriggerCenter
    }

    func getRegisteredBusinessIds() -> Set<String> {
        loadFromDisk()?.monitoredGeofenceIds ?? []
    }

    /// Distinct from `recordSync` (the fetch anchor), which a local re-rank leaves intact.
    func recordRegistration(center: LocationData, businessIds: Set<String>) {
        var state = loadFromDisk() ?? GeofenceState()
        state.movementTriggerCenter = center
        state.monitoredGeofenceIds = businessIds
        // A kept `.enter` baseline for an evicted region makes its next real arrival read as no change.
        if let records = state.monitorRegionRecords {
            let retained = businessIds.union([GeofenceConstants.movementTriggerIdentifier])
            state.monitorRegionRecords = records.filter { retained.contains($0.key) }
        }
        state.prunePolygonState(retaining: businessIds)
        state.dwellVisits = state.dwellVisits?.filter { businessIds.contains($0.key) }
        saveToDisk(state)
    }
}
