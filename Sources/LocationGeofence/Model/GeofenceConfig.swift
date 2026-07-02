import Foundation

/// Server-driven geofence configuration. Each field overrides the corresponding fallback
/// constant in `GeofenceConstants`; `GeofenceConfig.fallback` mirrors those constants for
/// callers that need a fully-formed default.
///
/// Persisted alongside the cached business geofences in `GeofenceState`. Decoders are
/// responsible for per-field sanitization (positive numerics, in-range counts) so any
/// `GeofenceConfig` instance is already valid.
///
/// `maxBusinessGeofences` is 0…19 on iOS: 20 monitored regions total, one slot reserved
/// for the SDK-built movement-trigger geofence. `0` is a valid server-side kill switch —
/// disables business region registration for the account without uninstalling the SDK.
struct GeofenceConfig: Codable, Equatable, Sendable {
    /// Movement-trigger geofence radius in meters. Default 3000m.
    let localRefreshTriggerRadius: Double
    /// Distance in meters from the last server fetch that triggers a fresh fetch. Used by
    /// `fetchNearby`; unread by `fetchAll`, which holds the whole workspace. See `GeofenceSyncMode`.
    let remoteFetchRefreshTriggerRadius: Double
    /// Freshness window for cached sync. A successful sync within this interval suppresses
    /// redundant API calls from identify / app-launch triggers.
    let remoteFetchRefreshExpiry: TimeInterval
    /// Duplicate-transition suppression window keyed by "geofenceId:transitionType".
    let duplicateEventsExpiry: TimeInterval
    /// Maximum number of business geofences to monitor. Always 0…19 on iOS (movement
    /// trigger consumes the 20th OS slot).
    let maxBusinessGeofences: Int
    /// Maximum distance in meters from the device at which a geofence is registered with the OS.
    /// Geofences beyond it are skipped and re-added by a later re-rank as the device moves closer;
    /// `GeofenceConstants.noMonitoringDistanceCap` means no cap. The server value and `fallback`
    /// apply `GeofenceConstants.defaultMaxMonitoringDistance` when the server omits it (see
    /// `GeofenceApiConfig.toDomain`).
    let maxMonitoringDistance: Double
}

extension GeofenceConfig {
    /// Mirrors `GeofenceConstants` for callers that need a fully-formed config when no
    /// cached value is available yet (first launch, pre-server-rollout, decode failure).
    static let fallback = GeofenceConfig(
        localRefreshTriggerRadius: GeofenceConstants.movementTriggerRadius,
        remoteFetchRefreshTriggerRadius: GeofenceConstants.serverFetchDistance,
        remoteFetchRefreshExpiry: GeofenceConstants.staleSyncInterval,
        duplicateEventsExpiry: GeofenceConstants.eventCooldownInterval,
        maxBusinessGeofences: GeofenceConstants.maxMonitoredGeofences,
        maxMonitoringDistance: GeofenceConstants.defaultMaxMonitoringDistance
    )
}
