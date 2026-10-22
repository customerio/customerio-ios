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
    /// A visit dropped while it still owes its reserved dwell, by any write, leaves that dwell in
    /// `orphanedDwells`.
    var dwellVisits: [String: GeofenceDwellVisit]? {
        didSet { orphanDwellsOwed(by: oldValue) }
    }

    /// Dwells their visits still owed when they were dropped — by an EXIT whose flush the outbox
    /// refused, a replacement, a pruned fence — oldest first, at most `maxOrphanedDwells`. Offered
    /// again at launch (`GeofenceDwellCoordinator.deliverOrphanedDwells`).
    var orphanedDwells: [GeofenceOrphanedDwell]?
    /// Per circle, the OS edges registered only for visit bookkeeping (see
    /// `Geofence.unconfiguredOsTransitions`). Outlives the fence's cache entry, which is the point:
    /// an OS callback for a fence the cache has dropped carries no configuration of its own.
    var unconfiguredOsTransitions: [String: Set<GeofenceTransition>]?
    /// The dwell coordinator's clock as an earlier process last saw it change: lets a new process
    /// tell whether an event dated before its first clock reading is on the wall clock now in force.
    var clockReference: GeofenceClockReading?
    /// The format `cachedGeofences` was written in; `nil` when an SDK older than dwell support
    /// wrote it, so its regions read as dwell-disabled whatever the server configured.
    /// Workspace-scoped like the catalog, so a user change keeps it.
    var catalogVersion: Int?
}

extension GeofenceState {
    /// 1: regions carry `dwellThresholdSeconds`.
    static let currentCatalogVersion = 1

    static let maxOrphanedDwells = 16

    /// Keeps the reserved dwell of every visit `old` held that owed one and is gone from
    /// `dwellVisits` now, or replaced by another visit. The oldest go first past the bound.
    private mutating func orphanDwellsOwed(by old: [String: GeofenceDwellVisit]?) {
        guard let old else { return }
        let dropped = old.sorted { $0.key < $1.key }.compactMap { geofenceId, visit -> GeofenceOrphanedDwell? in
            guard visit.owesDwell, let reservation = visit.dwellReservation,
                  dwellVisits?[geofenceId]?.visitId != visit.visitId
            else { return nil }
            return GeofenceOrphanedDwell(geofenceId: geofenceId, visitId: visit.visitId, userId: visit.userId, reservation: reservation)
        }
        guard !dropped.isEmpty else { return }
        let kept = (orphanedDwells ?? []).filter { orphan in !dropped.contains { $0.visitId == orphan.visitId } }
        orphanedDwells = Array((kept + dropped).suffix(Self.maxOrphanedDwells))
    }
}

/// A reserved dwell whose visit was dropped before it was delivered: enough to deliver it exactly
/// as reserved, for the user it was reserved under.
struct GeofenceOrphanedDwell: Codable, Equatable, Sendable {
    let geofenceId: String
    let visitId: String
    let userId: String
    let reservation: GeofenceDwellReservation
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
    /// A dwell written ahead of its admission, which becomes `dwellReservation` only once the
    /// admission, judged after the write, stands (`GeofenceStorage.admitStagedDwellReservation`).
    /// Never a fact about the stay: one an admission refused and could not take back, or that a
    /// process dying left, is replaced by the next attempt's and delivers nothing, so a relaunch
    /// asks for fresh proof rather than replaying it.
    var stagedDwellReservation: GeofenceDwellReservation?
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
    ///
    /// Kept exactly as the OS dated the event, to the last bit: the visit's own EXIT is recognised by
    /// comparing its date with this one for equality, and a different EXIT in the same millisecond
    /// must not match. The storage's seconds-since-1970 date encoding shifts many dates by a bit on
    /// the way through, so this is stored as the raw bits of its reference-date interval instead.
    var closedByObservedBoundary: Date?
    /// The newest inside evidence that proved the stay on its own — a fix whose accuracy disk lay
    /// wholly inside the fence (`recordInsideEvidence` with `qualifiesDwell`) — so an EXIT the OS
    /// did not date can bound its departure by it rather than by the entry. Nil until one is seen.
    var lastDecisiveInsideAt: Date?
    /// Location requests issued to prove this visit's dwell (`GeofenceDwellCoordinator.dwellProofBudget`),
    /// counted in memory as each is issued and persisted just after: a process dying in between loses
    /// at most that one. Persisted, so no re-arm, resume or relaunch replenishes the budget. Zero on
    /// visits persisted before the field.
    var dwellProofAttempts = 0
    /// When the latest of those requests was issued, to space the next one.
    var lastDwellProofRequest: GeofenceClockReading?
    /// Dwell evidence checks the visit's deadline and retries ran, answered from a request or not
    /// (`GeofenceDwellCoordinator.maxDwellProofChecks`). Persisted for the same reason. Zero on
    /// visits persisted before the field.
    var dwellProofChecks = 0

    /// Equal when they are the same stay with the same facts. `lastDecisiveInsideAt`, the
    /// dwell-proof bookkeeping and a staged reservation are left out: they record evidence sought
    /// and seen, or an admission not yet decided, not a fact of the stay.
    static func == (lhs: GeofenceDwellVisit, rhs: GeofenceDwellVisit) -> Bool {
        lhs.visitId == rhs.visitId && lhs.enteredAt == rhs.enteredAt && lhs.geometryRevision == rhs.geometryRevision
            && lhs.userId == rhs.userId && lhs.emitted == rhs.emitted && lhs.entryObserved == rhs.entryObserved
            && lhs.dwellReservation == rhs.dwellReservation && lhs.timing == rhs.timing
            && lhs.locationAccess == rhs.locationAccess && lhs.awaitsPresenceProof == rhs.awaitsPresenceProof
            && lhs.identityVersion == rhs.identityVersion && lhs.identityLineage == rhs.identityLineage
            && lhs.closedByObservedBoundary == rhs.closedByObservedBoundary
    }

    /// Whether a dwell was reserved on this visit and not yet delivered: a fact about the stay
    /// still owed to the outbox, which no loss of observation since may discard. Not one evidenced
    /// after the observed boundary that closed the visit: its fix may be a return's, so it is no
    /// dwell of this stay and is never delivered.
    var owesDwell: Bool {
        guard let dwellReservation, !emitted else { return false }
        return closedByObservedBoundary.map { !dwellReservation.isEvidenced(after: $0) } ?? true
    }
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

    /// Whether the evidence that qualified the dwell is dated after `date`, to the millisecond.
    func isEvidenced(after date: Date) -> Bool {
        occurredAtEpochMilliseconds > Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}

extension GeofenceDwellVisit {
    enum CodingKeys: String, CodingKey {
        case visitId, enteredAt, geometryRevision, userId, emitted, entryObserved, dwellReservation, stagedDwellReservation
        case timing, locationAccess, awaitsPresenceProof, identityVersion, identityLineage
        /// `closedByObservedBoundary`, as the decimal bit pattern of its `timeIntervalSinceReferenceDate`.
        case closedByObservedBoundaryReferenceBits
        case lastDecisiveInsideAt
        case dwellProofAttempts, lastDwellProofRequest, dwellProofChecks
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
        self.stagedDwellReservation = try container.decodeIfPresent(GeofenceDwellReservation.self, forKey: .stagedDwellReservation)
        self.timing = try container.decodeIfPresent(GeofenceVisitTiming.self, forKey: .timing)
        self.locationAccess = try container.decodeIfPresent(GeofenceLocationAccess.self, forKey: .locationAccess)
        self.identityVersion = try container.decodeIfPresent(UInt64.self, forKey: .identityVersion)
        self.identityLineage = try container.decodeIfPresent(String.self, forKey: .identityLineage)
        self.closedByObservedBoundary = try Self.decodeClosure(from: container)
        self.lastDecisiveInsideAt = try container.decodeIfPresent(Date.self, forKey: .lastDecisiveInsideAt)
        self.dwellProofAttempts = try container.decodeIfPresent(Int.self, forKey: .dwellProofAttempts) ?? 0
        self.lastDwellProofRequest = try container.decodeIfPresent(GeofenceClockReading.self, forKey: .lastDwellProofRequest)
        self.dwellProofChecks = try container.decodeIfPresent(Int.self, forKey: .dwellProofChecks) ?? 0
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
        try container.encodeIfPresent(stagedDwellReservation, forKey: .stagedDwellReservation)
        try container.encodeIfPresent(timing, forKey: .timing)
        try container.encodeIfPresent(locationAccess, forKey: .locationAccess)
        try container.encode(awaitsPresenceProof, forKey: .awaitsPresenceProof)
        // Null rather than absent when unknown: absent marks a visit from before the field.
        try container.encode(identityVersion, forKey: .identityVersion)
        try container.encode(identityLineage, forKey: .identityLineage)
        try container.encodeIfPresent(
            closedByObservedBoundary.map { String($0.timeIntervalSinceReferenceDate.bitPattern) },
            forKey: .closedByObservedBoundaryReferenceBits
        )
        try container.encodeIfPresent(lastDecisiveInsideAt, forKey: .lastDecisiveInsideAt)
        if dwellProofAttempts > 0 { try container.encode(dwellProofAttempts, forKey: .dwellProofAttempts) }
        try container.encodeIfPresent(lastDwellProofRequest, forKey: .lastDwellProofRequest)
        if dwellProofChecks > 0 { try container.encode(dwellProofChecks, forKey: .dwellProofChecks) }
    }

    /// The closure exactly as encoded; nil when the key is absent. Bits that are not a finite
    /// interval are rejected rather than read as no closure, which would let a closed visit resume.
    private static func decodeClosure(from container: KeyedDecodingContainer<CodingKeys>) throws -> Date? {
        guard let bits = try container.decodeIfPresent(String.self, forKey: .closedByObservedBoundaryReferenceBits) else {
            return nil
        }
        guard let pattern = UInt64(bits), Double(bitPattern: pattern).isFinite else {
            throw DecodingError.dataCorruptedError(
                forKey: .closedByObservedBoundaryReferenceBits, in: container, debugDescription: "Not a finite interval: \(bits)"
            )
        }
        return Date(timeIntervalSinceReferenceDate: Double(bitPattern: pattern))
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
    /// When an EXIT was last recorded for this circle, on the monotonic timeline of the reading its
    /// producer took, kept when an ENTER replaces that state. For a polygon's covering circle it is
    /// departure evidence the polygon's late crossing is judged by, though the EXIT's routing was
    /// lost. Nil until an EXIT with a reading has been recorded.
    var lastObservedOutside: GeofenceClockStamp?
}
