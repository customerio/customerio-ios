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
/// - `fetchNearby` — sends a coarsened device coordinate (see `CoordinateCoarsener`) so the backend
///   returns the set ranked around the device, and refetches when the device moves beyond
///   `GeofenceConfig.remoteFetchRefreshTriggerRadius` from the last fetch anchor.
/// - `fetchAll` — sends no location; the backend returns the full (capped) workspace set.
///
/// Both modes are fully implemented; `active` selects the one the SDK ships with. It is
/// **compile-time only** — never a runtime or server-pushed toggle — so whether location is sent can
/// only change in a deliberate SDK release.
enum GeofenceSyncMode: Equatable {
    case fetchAll
    case fetchNearby

    /// The mode the SDK ships with. Compile-time only — see the type doc.
    static let active: GeofenceSyncMode = .fetchNearby
}
