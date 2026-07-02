import CioInternalCommon
import Foundation

/// Persisted state for geofence monitoring.
/// Fields are optional so partial state (e.g. only cooldowns) can be stored without requiring all fields.
struct GeofenceState: Codable, Equatable, Sendable {
    /// Geofences cached from the last server fetch.
    var cachedGeofences: [Geofence]?
    /// Location where the last server sync was performed.
    var lastServerSyncLocation: LocationData?
    /// Timestamp of the last server sync.
    var lastServerSyncTimestamp: Date?
    /// IDs of business geofences currently being monitored by the OS.
    var monitoredGeofenceIds: Set<String>?
    /// Center of the current Movement Trigger Geofence.
    var movementTriggerCenter: LocationData?
    /// Cooldown records for geofence transition events, keyed by "geofenceId:transitionType".
    var eventCooldowns: [String: Date]?
    /// Server-driven configuration from the last successful sync. `nil` when no sync has
    /// landed a `config` block yet — consumers fall back to `GeofenceConfig.fallback` or
    /// their component defaults.
    var cachedConfig: GeofenceConfig?
}
