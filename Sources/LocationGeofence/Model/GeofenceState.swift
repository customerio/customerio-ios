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
    /// The dwell coordinator's clock as an earlier process last saw it change: lets a new process
    /// tell whether an event dated before its first clock reading is on the wall clock now in force.
    var clockReference: GeofenceClockReading?
}

struct GeofenceDwellVisit: Codable, Equatable, Sendable {
    let visitId: String
    let enteredAt: Date
    let geometryRevision: String
    let userId: String
    var emitted: Bool
    /// False for a candidate started from mid-visit inside evidence after continuity was lost: it
    /// can still support a best-effort dwell, but its start is not an entry, so the dwell reports
    /// neither `enteredAt` nor a duration.
    var entryObserved = true
    /// The dwell this visit qualified, fixed before its outbox write. Every attempt to deliver the
    /// dwell sends exactly this, so a retry after a failed `emitted` write or a relaunch repeats
    /// the first attempt's row rather than describing a later instant under the same visit id.
    var dwellReservation: GeofenceDwellReservation?
    /// The monotonic timeline and boot the entry was recorded on. Nil on visits persisted before
    /// the field: nothing says which boot they began on, so they support no dwell.
    let timing: GeofenceVisitTiming?
    /// The location access in force when the visit was recorded; nil when unknown.
    var locationAccess: GeofenceLocationAccess?
    /// A candidate discovered from a location nothing proved current — the refresh anchor — rather
    /// than from an OS crossing or a fresh fix. Its time counts toward nothing until the first fresh
    /// inside fix, which re-starts it from that fix. See the decoder for visits persisted before
    /// the field.
    var awaitsPresenceProof = false
    /// The context store's identity version the visit was recorded under (`GeofenceIdentity`): the
    /// visit holds only while that is still the version. Nil when no store was observed; always
    /// written, as null then, so a visit without the key is known to predate it.
    var identityVersion: UInt64?
    /// The lineage `identityVersion` counts in, stamped with it; the visit holds only while both
    /// are still the store's. Always written, like `identityVersion`.
    var identityLineage: String?
    /// The OS date of the observed EXIT, or crossing ENTER, that `CLMonitor` recorded as ending this
    /// circle visit, written in the same storage write as the monitor's record (see
    /// `GeofenceStorage.closeVisit`). Survives a process dying before the visit's removal, so the
    /// visit never qualifies a first dwell, nor is adopted, after it. Set once; nil when none.
    var closedByObservedBoundary: Date?
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
    enum CodingKeys: String, CodingKey {
        case visitId, enteredAt, geometryRevision, userId, emitted, entryObserved, dwellReservation
        case timing, locationAccess, awaitsPresenceProof, identityVersion, identityLineage
        case closedByObservedBoundary
    }

    /// Custom decode so visits persisted before `entryObserved` still decode; those were only ever
    /// started from an observed entry. Visits persisted before `dwellReservation`, `timing` or
    /// `locationAccess` hold none.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.visitId = try container.decode(String.self, forKey: .visitId)
        self.enteredAt = try container.decode(Date.self, forKey: .enteredAt)
        self.geometryRevision = try container.decode(String.self, forKey: .geometryRevision)
        self.userId = try container.decode(String.self, forKey: .userId)
        self.emitted = try container.decode(Bool.self, forKey: .emitted)
        self.entryObserved = try container.decodeIfPresent(Bool.self, forKey: .entryObserved) ?? true
        self.dwellReservation = try container.decodeIfPresent(GeofenceDwellReservation.self, forKey: .dwellReservation)
        self.timing = try container.decodeIfPresent(GeofenceVisitTiming.self, forKey: .timing)
        self.locationAccess = try container.decodeIfPresent(GeofenceLocationAccess.self, forKey: .locationAccess)
        self.identityVersion = try container.decodeIfPresent(UInt64.self, forKey: .identityVersion)
        self.identityLineage = try container.decodeIfPresent(String.self, forKey: .identityLineage)
        self.closedByObservedBoundary = try container.decodeIfPresent(Date.self, forKey: .closedByObservedBoundary)
        let unqualified = !emitted && dwellReservation == nil
        guard container.contains(.identityVersion) else {
            // Written before identity provenance: nothing says which identities the visit spanned,
            // nor whether it was a stale-anchor discovery. Its entry is not reported, and while its
            // dwell is unqualified its time counts from its next fresh proof. A reserved or emitted
            // dwell keeps its id and its facts exactly as they are: it is never qualified again.
            self.entryObserved = false
            self.awaitsPresenceProof = unqualified
            return
        }
        // Earlier builds with provenance persisted stale-anchor discoveries as unknown-entry
        // candidates; the flag tells them apart where present.
        self.awaitsPresenceProof = try container.decodeIfPresent(Bool.self, forKey: .awaitsPresenceProof)
            ?? (!entryObserved && unqualified)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(visitId, forKey: .visitId)
        try container.encode(enteredAt, forKey: .enteredAt)
        try container.encode(geometryRevision, forKey: .geometryRevision)
        try container.encode(userId, forKey: .userId)
        try container.encode(emitted, forKey: .emitted)
        try container.encode(entryObserved, forKey: .entryObserved)
        try container.encodeIfPresent(dwellReservation, forKey: .dwellReservation)
        try container.encodeIfPresent(timing, forKey: .timing)
        try container.encodeIfPresent(locationAccess, forKey: .locationAccess)
        try container.encode(awaitsPresenceProof, forKey: .awaitsPresenceProof)
        // Null rather than absent when unknown: absent marks a visit from before the field.
        try container.encode(identityVersion, forKey: .identityVersion)
        try container.encode(identityLineage, forKey: .identityLineage)
        try container.encodeIfPresent(closedByObservedBoundary, forKey: .closedByObservedBoundary)
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
    /// inside all along: no crossing a visit can date from. Optional for records persisted before
    /// the field; `nil` counts as assumed.
    var lastStateObserved: Bool?
}
