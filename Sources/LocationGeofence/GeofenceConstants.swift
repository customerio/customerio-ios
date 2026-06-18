import Foundation

/// Constants used across geofence components.
enum GeofenceConstants {
    /// Region identifier for the Movement Trigger Geofence.
    static let movementTriggerIdentifier = "cio_movement_trigger"

    /// Maximum number of business geofences to monitor.
    /// iOS allows 20 total monitored regions; 1 is reserved for the movement trigger.
    static let maxMonitoredGeofences = 19

    /// Fallback for `localRefreshTriggerRadius` (meters) — the movement-trigger geofence radius and
    /// the ranking-staleness threshold. Server config overrides it.
    static let movementTriggerRadius: Double = 3000

    /// Fallback for `remoteFetchRefreshTriggerRadius` (meters) — distance from the last API fetch at
    /// which the `nearby` mode re-fetches. Unused by `fetchAll` (movement never re-fetches). Server
    /// config overrides it.
    static let serverFetchDistance: Double = 20000

    /// Cooldown interval (in seconds) for suppressing duplicate enter/exit events for the same geofence.
    static let eventCooldownInterval: TimeInterval = 1 * 60 * 60

    /// Staleness interval (in seconds) after which a server sync is considered stale.
    static let staleSyncInterval: TimeInterval = 24 * 60 * 60
}
