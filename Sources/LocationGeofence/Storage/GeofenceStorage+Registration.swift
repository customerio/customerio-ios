import CioInternalCommon
import Foundation

/// The registration anchor and its registered set, split out to keep `GeofenceStorage` readable
/// (same convention as `+PolygonMembership`). Members are `internal` only because they live in a
/// separate file from `loadFromDisk`/`saveToDisk`; they remain storage implementation detail.
extension GeofenceStorage {
    /// Center of the most recent OS registration (the movement-trigger center). The sync
    /// decision measures distance from here to detect a stale ranking — the device moved
    /// beyond the trigger radius while the app was dead, so the registered nearest-set is
    /// no longer the closest geofences and needs a local re-rank.
    func getLastRegistrationCenter() -> LocationData? {
        loadFromDisk()?.movementTriggerCenter
    }

    /// Business geofence IDs registered with the OS at the last registration. Lets the sync
    /// decision spot a cache that holds regions while nothing is registered (e.g. regs lost
    /// on sign-out) and re-register instead of skipping.
    func getRegisteredBusinessIds() -> Set<String> {
        loadFromDisk()?.monitoredGeofenceIds ?? []
    }

    /// Records the registration anchor + business IDs in one load-modify-save. Updated on every
    /// registration, including a local re-rank, so the ranking-staleness reference follows the
    /// device. Distinct from `recordSync` (the API-fetch anchor), which a local re-rank leaves intact.
    func recordRegistration(center: LocationData, businessIds: Set<String>) {
        var state = loadFromDisk() ?? GeofenceState()
        state.movementTriggerCenter = center
        state.monitoredGeofenceIds = businessIds
        // Drop per-condition baselines for regions this registration no longer covers. A record
        // survives `stopMonitoring` on purpose, so an unchanged re-register keeps its baseline and
        // CLMonitor's re-evaluation stays silent — but a region *evicted* from the set is a
        // different case. It goes unmonitored, so no EXIT ever balances a `.enter` baseline, and a
        // later re-registration with the same circle keeps that stale value instead of the state
        // the device is actually in. The next genuine arrival then reads as no change and is
        // dropped. Retaining exactly the registered set bounds the records the same way
        // `monitoredGeofenceIds` is bounded, and clears anything a previous version stranded.
        if let records = state.monitorRegionRecords {
            let retained = businessIds.union([GeofenceConstants.movementTriggerIdentifier])
            state.monitorRegionRecords = records.filter { retained.contains($0.key) }
        }
        state.prunePolygonState(retaining: businessIds)
        saveToDisk(state)
    }
}
