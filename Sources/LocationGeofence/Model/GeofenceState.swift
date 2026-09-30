import CioInternalCommon
import Foundation

/// Fields are optional so partial state (e.g. only cooldowns) can be stored.
struct GeofenceState: Codable, Equatable, Sendable {
    var cachedGeofences: [Geofence]?
    var lastServerSyncLocation: LocationData?
    var lastServerSyncTimestamp: Date?
    var monitoredGeofenceIds: Set<String>?
    var movementTriggerCenter: LocationData?
    /// Keyed by "userId:geofenceId:transitionType".
    var eventCooldowns: [String: Date]?
    var cachedConfig: GeofenceConfig?
    /// Absent for circles and for polygons no fix has decided yet.
    var polygonMembership: [String: PolygonMembershipRecord]?
    /// CLMonitor (iOS 18+) only; `nil` on the classic path, which needs no dedup or filtering.
    var monitorRegionRecords: [String: MonitorRegionRecord]?
}

/// `CLMonitor` re-emits a condition's current state on start and re-evaluation, and reports both
/// enter and exit: `lastState` suppresses the re-emissions, `transitionTypes` filters delivery.
struct MonitorRegionRecord: Codable, Equatable, Sendable {
    /// Updated on every observed event, including ones filtered from delivery.
    var lastState: GeofenceTransition
    var transitionTypes: Set<GeofenceTransition>
    /// Tells an unchanged re-registration (keep the baseline) from a changed circle (reseed). `nil`
    /// counts as changed.
    var center: LocationData?
    var radius: Double?
    /// Re-emissions of an unchanged state don't move it. The baseline heal only trusts a fix newer
    /// than this; `nil` never blocks a heal.
    var lastStateChangedAt: Date?
    /// Kept on an unchanged re-registration. An OS event dated before it is refused; `nil` refuses
    /// nothing.
    var registeredAt: Date?
    /// CoreLocation repeats an event, not always in date order; one dated at or before this is a
    /// repeat. `nil` refuses nothing.
    var lastEventDate: Date?
}
