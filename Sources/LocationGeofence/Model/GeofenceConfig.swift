import Foundation

/// Server-driven geofence configuration. Each field overrides the corresponding fallback
/// constant in `GeofenceConstants`; `fallback` mirrors those constants.
///
/// Persisted in `GeofenceState`. `GeofenceApiConfig.toDomain` sanitizes every field, so any
/// instance is already valid.
struct GeofenceConfig: Codable, Equatable, Sendable {
    /// Movement-trigger geofence radius in meters.
    let localRefreshTriggerRadius: Double
    /// Distance in meters from the last server fetch that triggers a fresh nearby fetch.
    let remoteFetchRefreshTriggerRadius: Double
    /// Freshness window for cached sync. A successful sync within this interval suppresses
    /// redundant API calls from identify / app-launch triggers.
    let remoteFetchRefreshExpiry: TimeInterval
    /// Duplicate-transition suppression window keyed by "userId:geofenceId:transitionType".
    let duplicateEventsExpiry: TimeInterval
    /// Maximum number of business geofences to monitor. Always 0…19 on iOS (the movement
    /// trigger takes the 20th OS slot). `0` is the server-driven kill switch: nothing registers,
    /// not even the movement trigger.
    let maxBusinessGeofences: Int
    /// Maximum distance in meters from the device at which a geofence is registered with the OS.
    /// Geofences beyond it are skipped and re-added by a later re-rank as the device moves closer;
    /// `GeofenceConstants.noMonitoringDistanceCap` means no cap. Defaults to
    /// `GeofenceConstants.defaultMaxMonitoringDistance` when the server omits it.
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
