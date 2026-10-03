import Foundation

/// Server overrides of `GeofenceConstants`. `GeofenceApiConfig.toDomain` sanitizes every field.
struct GeofenceConfig: Codable, Equatable, Sendable {
    /// Movement-trigger radius in meters.
    let localRefreshTriggerRadius: Double
    /// Distance in meters from the last server fetch that triggers a fresh nearby fetch.
    let remoteFetchRefreshTriggerRadius: Double
    /// A sync within this window suppresses identify / app-launch fetches.
    let remoteFetchRefreshExpiry: TimeInterval
    /// Keyed by "userId:geofenceId:transitionType".
    let duplicateEventsExpiry: TimeInterval
    /// 0…19 on iOS (the movement trigger takes the 20th OS slot). `0` is the kill switch: nothing
    /// registers, not even the movement trigger.
    let maxBusinessGeofences: Int
    /// Meters from the device. `GeofenceConstants.noMonitoringDistanceCap` means no cap.
    let maxMonitoringDistance: Double
}

extension GeofenceConfig {
    static let fallback = GeofenceConfig(
        localRefreshTriggerRadius: GeofenceConstants.movementTriggerRadius,
        remoteFetchRefreshTriggerRadius: GeofenceConstants.serverFetchDistance,
        remoteFetchRefreshExpiry: GeofenceConstants.staleSyncInterval,
        duplicateEventsExpiry: GeofenceConstants.eventCooldownInterval,
        maxBusinessGeofences: GeofenceConstants.maxMonitoredGeofences,
        maxMonitoringDistance: GeofenceConstants.defaultMaxMonitoringDistance
    )
}
