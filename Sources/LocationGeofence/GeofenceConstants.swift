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

    /// Fallback for `remoteFetchRefreshTriggerRadius` (meters): how far the device must move from the
    /// last fetch anchor before a location-bound sync (`GeofenceSyncMode.fetchNearby`) refetches a
    /// fresh nearby set. Unused by `fetchAll`, which holds the complete workspace. See `GeofenceSyncMode`.
    static let serverFetchDistance: Double = 20000

    /// Default `maxMonitoringDistance` (meters) applied when the server omits the field — which it
    /// does today. A finite cap (not "unlimited") so a device far from a workspace's geofences (e.g.
    /// in the US with geofences in Europe) doesn't burn OS slots on regions it can't reach soon;
    /// local re-rank re-adds them as the device approaches. The server can send an explicit `0` to
    /// disable the cap (mapped to `noMonitoringDistanceCap`).
    static let defaultMaxMonitoringDistance: Double = 1000000 // 1000 km

    /// Sentinel for "no distance cap" — every candidate registers regardless of distance. Used when
    /// the server explicitly sends `0`.
    static let noMonitoringDistanceCap: Double = .greatestFiniteMagnitude

    /// Cooldown interval (in seconds) for suppressing duplicate enter/exit events for the same geofence.
    static let eventCooldownInterval: TimeInterval = 1 * 60 * 60

    /// Staleness interval (in seconds) after which a server sync is considered stale.
    static let staleSyncInterval: TimeInterval = 24 * 60 * 60

    // Sane bounds the SDK coerces server config into, so a misconfigured backend can't push
    // monitoring into a pathological state: a positive out-of-range value clamps to the nearest
    // bound; a non-positive value falls back. (`maxMonitoringDistance` needs no upper bound — a
    // huge value just means "no cap" — and is separately disabled when below the trigger radius.)
    static let minLocalRefreshRadius: Double = 100
    static let maxLocalRefreshRadius: Double = 5000
    static let minRemoteFetchRefreshExpiry: TimeInterval = 60 // 1 minute
    static let maxRemoteFetchRefreshExpiry: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    static let minDuplicateEventsExpiry: TimeInterval = 60 // 1 minute
    static let maxDuplicateEventsExpiry: TimeInterval = 24 * 60 * 60 // 24 hours
}
