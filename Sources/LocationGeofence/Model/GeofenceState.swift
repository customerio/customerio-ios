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
    /// Cooldown records for geofence transition events, keyed by "userId:geofenceId:transitionType".
    var eventCooldowns: [String: Date]?
    /// Server-driven configuration from the last successful sync. `nil` when no sync has
    /// landed a `config` block yet — consumers fall back to `GeofenceConfig.fallback` or
    /// their component defaults.
    var cachedConfig: GeofenceConfig?
    /// Believed device membership for each polygon geofence, keyed by geofence id. Absent for
    /// circle fences, and absent for a polygon no fix has yet decided (see `PolygonMembership`).
    var polygonMembership: [String: PolygonMembershipRecord]?
    /// Per-condition bookkeeping for the CLMonitor (iOS 17+) monitor, keyed by region identifier.
    /// `nil` on the classic CLLocationManager path, which needs neither: its delegate fires only on
    /// real crossings (no dedup needed) and filters transition types at the OS level.
    var monitorRegionRecords: [String: MonitorRegionRecord]?
    /// One durable continuous visit per fence. Cleared on exit, user change, or geometry change.
    var dwellVisits: [String: GeofenceDwellVisit]?
    /// Per circle, the OS edges registered only for visit bookkeeping (see
    /// `Geofence.unconfiguredOsTransitions`). Outlives the fence's cache entry, which is the point:
    /// an OS callback for a fence the cache has dropped carries no configuration of its own.
    var unconfiguredOsTransitions: [String: Set<GeofenceTransition>]?
}

struct GeofenceDwellVisit: Codable, Equatable, Sendable {
    let visitId: String
    let enteredAt: Date
    let geometryRevision: String
    let userId: String
    var emitted: Bool
    /// False for a candidate started from mid-visit inside evidence after continuity was lost: it
    /// can still support a best-effort dwell, but its start is not an entry, so its EXIT carries no
    /// visit duration.
    var entryObserved = true
    /// The dwell this visit qualified, fixed before its outbox write. Every attempt to deliver the
    /// dwell sends exactly this, so a retry after a failed `emitted` write or a relaunch repeats
    /// the first attempt's row rather than describing a later instant under the same visit id.
    var dwellReservation: GeofenceDwellReservation?
}

/// A dwell occurrence, stored as integer epoch milliseconds so a disk round trip cannot move it: a
/// `Date` read back through `.secondsSince1970` can land one ulp off, which on a whole second
/// changes the outbox key and the reported seconds.
struct GeofenceDwellReservation: Codable, Equatable, Sendable {
    /// The event's timestamp in epoch milliseconds, the precision the wire carries.
    let occurredAtEpochMilliseconds: Int64
    /// The reported entry; nil when the entry was not observed.
    let enteredAtEpochMilliseconds: Int64?
    let durationSeconds: Int?
    let thresholdSeconds: Int
    let detectionSource: String

    var occurredAt: Date {
        Date(timeIntervalSince1970: TimeInterval(occurredAtEpochMilliseconds) / 1000)
    }

    var enteredAt: Date? {
        enteredAtEpochMilliseconds.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
    }
}

extension GeofenceDwellVisit {
    /// Custom decode so visits persisted before `entryObserved` still decode; those were only ever
    /// started from an observed entry. Visits persisted before `dwellReservation` hold none.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.visitId = try container.decode(String.self, forKey: .visitId)
        self.enteredAt = try container.decode(Date.self, forKey: .enteredAt)
        self.geometryRevision = try container.decode(String.self, forKey: .geometryRevision)
        self.userId = try container.decode(String.self, forKey: .userId)
        self.emitted = try container.decode(Bool.self, forKey: .emitted)
        self.entryObserved = try container.decodeIfPresent(Bool.self, forKey: .entryObserved) ?? true
        self.dwellReservation = try container.decodeIfPresent(GeofenceDwellReservation.self, forKey: .dwellReservation)
    }
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
    /// Registered circle center. Lets `recordMonitorRegistration` tell an unchanged re-registration
    /// (preserve the baseline) from a new/changed circle (reseed) — the live `CLMonitor` record can't,
    /// since the wholesale stop-all removes it before every re-add. Optional so records persisted before
    /// this field decode; a nil-geometry record is treated as changed and reseeded once.
    var center: LocationData?
    /// Registered radius in meters; paired with `center` for the unchanged-geometry check.
    var radius: Double?
    /// When `lastState` was last written (registration seed or observed state change; re-emissions
    /// of an unchanged state don't move it). The baseline heal only trusts a fix newer than this —
    /// an older fix judging a newer baseline would synthesize the reverse of the crossing that set
    /// it. Optional so records persisted before this field decode; `nil` never blocks a heal.
    var lastStateChangedAt: Date?
    /// When the circle this record describes was installed at the OS — set on a new identifier, a
    /// changed circle or a forced reseed, preserved on an unchanged re-registration. An OS event
    /// dated before it was computed against a circle that no longer exists and is refused, whatever
    /// its state says. Optional for records persisted before the field; `nil` refuses nothing.
    var registeredAt: Date?
    /// The OS date of the last event processed for this condition. CoreLocation delivers one event
    /// two to three times, not always in date order and not always with an identical date; an event
    /// dated at or before this one has already been seen. Optional for records persisted before the
    /// field; `nil` refuses nothing.
    var lastEventDate: Date?
}
