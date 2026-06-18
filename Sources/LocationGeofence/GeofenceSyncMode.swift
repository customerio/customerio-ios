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
/// `fetchAll` is the active default: the backend returns the full (capped) set and the SDK never
/// sends device location to fetch.
///
/// `nearby` sends coarse location and lets the backend return only nearby geofences. It is retained
/// and tested so location-based fetch can be re-enabled in a later phase by changing `active` — that
/// also needs backend support and is a deliberate SDK release, never a runtime or server-pushed
/// toggle (which would re-introduce the ability to silently start sending location).
enum GeofenceSyncMode: Equatable {
    case fetchAll
    case nearby

    /// `nearby`'s set is location-bound, so it re-fetches once the device outruns it; `fetchAll`
    /// holds the full set, so movement never re-fetches.
    func movementRequiresRemoteFetch(distanceFromAnchor: Double, config: GeofenceConfig) -> Bool {
        switch self {
        case .nearby: return distanceFromAnchor >= config.remoteFetchRefreshTriggerRadius
        case .fetchAll: return false
        }
    }

    /// The mode the SDK ships with. Compile-time only — see the type doc.
    static let active: GeofenceSyncMode = .fetchAll
}
