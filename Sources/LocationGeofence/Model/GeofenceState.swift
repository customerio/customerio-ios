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
    /// Per-condition bookkeeping for the CLMonitor (iOS 17+) monitor, keyed by region identifier.
    /// `nil` on the classic CLLocationManager path, which needs neither: its delegate fires only on
    /// real crossings (no dedup needed) and filters transition types at the OS level.
    var monitorRegionRecords: [String: MonitorRegionRecord]?
}

/// Bookkeeping the CLMonitor (iOS 17+) monitor keeps per registered condition.
///
/// `CLMonitor` re-emits a condition's CURRENT state on process start and system re-evaluation
/// (unlock/foreground), not just on boundary crossings, and always reports both enter and exit —
/// there is no `notifyOnEntry`/`notifyOnExit` equivalent. `lastState` suppresses the re-emissions
/// (persisted so a cold-wake compares against the pre-kill state); `transitionTypes` restores the
/// per-region delivery filter the classic path gets from the OS.
struct MonitorRegionRecord: Codable, Equatable, Sendable {
    /// Last state observed for the condition — the dedup baseline. Seeded at registration (see
    /// `GeofenceStorage.recordMonitorRegistration`) and updated on every observed event thereafter,
    /// including ones filtered from delivery.
    var lastState: GeofenceTransition
    /// Transition types the region was registered for; events of other types are recorded but not delivered.
    var transitionTypes: Set<GeofenceTransition>
}
