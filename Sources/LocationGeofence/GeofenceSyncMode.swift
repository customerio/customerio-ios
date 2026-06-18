import Foundation

/// The kind of refresh a signal calls for, decided independently of what triggered it.
///
/// - `remote` — fetch a fresh set from the API.
/// - `local`  — re-rank / re-register the cached set on-device, no network.
/// - `skip`   — cache is current; do nothing.
enum RefreshAction: Equatable {
    case remote
    case local
    case skip
}

/// How the SDK fetches a user's geofences.
///
/// `fetchAll` is the only mode: the backend returns the full (capped) set and the SDK never sends
/// device location to fetch. This is a deliberate privacy posture — there is intentionally no code
/// path that transmits location off-device.
///
/// To re-introduce a location-bound mode later (needs backend support; a deliberate SDK release,
/// never a runtime or server-pushed toggle that could silently start sending location): add a case
/// here, restore the coordinate coarsener + `GeofenceApiService.fetchNearbyGeofences`, branch on it
/// in `GeofenceSyncCoordinator.awaitApiFetch`, and re-add the movement re-fetch rule (compare
/// distance-from-last-fetch against `GeofenceConfig.remoteFetchRefreshTriggerRadius`) in the refresh
/// and `handleMovement` decisions.
enum GeofenceSyncMode: Equatable {
    case fetchAll

    /// The mode the SDK ships with. Compile-time only — see the type doc.
    static let active: GeofenceSyncMode = .fetchAll
}
