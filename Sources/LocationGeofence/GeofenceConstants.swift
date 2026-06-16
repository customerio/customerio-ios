import Foundation

/// Constants used across geofence components.
enum GeofenceConstants {
    /// Region identifier for the Movement Trigger Geofence.
    static let movementTriggerIdentifier = "cio_movement_trigger"

    /// Maximum number of business geofences to monitor.
    /// iOS allows 20 total monitored regions; 1 is reserved for the movement trigger.
    static let maxMonitoredGeofences = 19

    /// Radius of the Movement Trigger Geofence in meters.
    static let movementTriggerRadius: Double = 1000

    /// Distance from last server sync (in meters) that triggers a new server fetch.
    static let serverFetchDistance: Double = 3000

    /// Cooldown interval (in seconds) for suppressing duplicate enter/exit events for the same geofence.
    static let eventCooldownInterval: TimeInterval = 1 * 60 * 60

    /// Staleness interval (in seconds) after which a server sync is considered stale.
    static let staleSyncInterval: TimeInterval = 24 * 60 * 60
}
