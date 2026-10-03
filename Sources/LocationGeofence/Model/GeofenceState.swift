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
    /// Whether `lastState` was observed — an OS-reported change, or a fix that settled the side —
    /// rather than assumed at registration. `CLMonitor` answers a wrong `assuming:` with an event of
    /// the real state, so an ENTER out of an assumed `.exit` can be that correction for a device
    /// inside all along, and an EXIT out of an assumed `.enter` one for a device never inside:
    /// neither is a crossing a visit can be timed by. Optional for records persisted before the
    /// field; `nil` counts as assumed.
    var lastStateObserved: Bool?
}
