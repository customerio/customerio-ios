import Foundation

/// A moment placed on the monotonic timeline of the boot it was recorded on, so it can be ordered
/// against a visit's entry whatever the wall clock has done since: a clock set back makes a newer
/// visit's wall date earlier than older evidence, which uptime never does.
struct GeofenceClockStamp: Codable, Equatable, Sendable {
    let boot: GeofenceBootIdentity
    /// `date` mapped to uptime when it was recorded (`GeofenceVisitTiming.uptime(of:at:)`).
    let uptime: TimeInterval

    init(date: Date, at reading: GeofenceClockReading) {
        self.boot = reading.boot
        self.uptime = GeofenceVisitTiming.uptime(of: date, at: reading)
    }

    /// Whether this moment came after `visit` began. Only on the boot both were recorded on: across
    /// boots, or for a visit without timing, nothing orders them, and the answer is no.
    func isAfterEntry(of visit: GeofenceDwellVisit) -> Bool {
        guard let timing = visit.timing, boot.isSameBoot(as: timing.boot) else { return false }
        return uptime > timing.enteredUptime
    }

    /// The later of two stamps on one boot; across boots, `other`, the one recorded since.
    func newer(_ other: GeofenceClockStamp?) -> GeofenceClockStamp {
        guard let other else { return self }
        guard boot.isSameBoot(as: other.boot) else { return other }
        return other.uptime > uptime ? other : self
    }
}

/// Where a visit's entry sits on the monotonic timeline, stored next to its wall-clock entry. It is
/// what lets the visit's elapsed time be measured without trusting the wall clock, and what tells
/// a visit recorded on an earlier boot from one on this boot.
struct GeofenceVisitTiming: Codable, Equatable, Sendable {
    let boot: GeofenceBootIdentity
    /// Uptime of the entry, estimated from its date. Orders the visit against other boundary
    /// events, which the wall clock cannot once it has stepped.
    let enteredUptime: TimeInterval
    /// Uptime when the SDK recorded the visit. Never earlier than the entry, so time measured from
    /// it cannot overstate the stay, whatever the wall clock did before the entry was processed.
    let recordedUptime: TimeInterval
    /// `GeofenceClockReading.wallOffset` when recorded.
    let wallOffset: TimeInterval

    init(enteredAt: Date, recordedAt reading: GeofenceClockReading) {
        self.boot = reading.boot
        self.enteredUptime = Self.uptime(of: enteredAt, at: reading)
        self.recordedUptime = reading.uptime
        self.wallOffset = reading.wallOffset
    }

    /// Whether `reading` was taken on the boot this visit was recorded on. Uptime behind the
    /// record can only be a later boot.
    func isCurrent(at reading: GeofenceClockReading) -> Bool {
        bootRelation(at: reading) == .same
    }

    /// How the boot of `reading` relates to the one this visit was recorded on.
    func bootRelation(at reading: GeofenceClockReading) -> GeofenceBootRelation {
        if reading.uptime < recordedUptime { return .knownOther }
        return boot.isSameBoot(as: reading.boot) ? .same : .ambiguous
    }

    /// The entry's uptime, to order it against an event processed at `reading`. Minus infinity on
    /// another boot, whose uptime orders nothing against this one: such an event was processed after
    /// this visit was recorded, so it is the later.
    func entryUptime(orderedAt reading: GeofenceClockReading) -> TimeInterval {
        isCurrent(at: reading) ? enteredUptime : -.infinity
    }

    /// Whether a loss of continuity seen at `loss` interrupted this visit: it was entered no later
    /// than the loss, or on another boot.
    func spans(_ loss: GeofenceClockReading) -> Bool {
        !boot.isSameBoot(as: loss.boot) || enteredUptime <= loss.uptime
    }

    /// Whether the wall clock kept step with uptime between recording and `reading`, so wall dates
    /// from either side of it are on one timeline.
    func wallClockAgrees(at reading: GeofenceClockReading) -> Bool {
        abs(reading.wallOffset - wallOffset) <= GeofenceConstants.dwellWallClockStepTolerance
    }

    /// The uptime of an event dated `date` and processed at `reading`: the reading's uptime less
    /// the event's wall-clock age. Never later than the reading, as an event cannot postdate its
    /// processing, so a date a clock change put in the future reads as the reading itself.
    static func uptime(of date: Date, at reading: GeofenceClockReading) -> TimeInterval {
        reading.uptime - max(0, reading.wall.timeIntervalSince(date))
    }

    /// The visit's length up to an event dated `date` and processed at `reading`. Nil when the
    /// reading is from another boot, which no elapsed time can be measured across.
    ///
    /// For dwell qualification and for any visit duration: a duration may be reported as wall
    /// time from `enteredAt` to `date` only when `wallClockAgrees`.
    func elapsed(enteredAt: Date, until date: Date, at reading: GeofenceClockReading) -> GeofenceVisitElapsed? {
        guard isCurrent(at: reading) else { return nil }
        let monotonic = Self.uptime(of: date, at: reading) - recordedUptime
        let agrees = wallClockAgrees(at: reading)
        return GeofenceVisitElapsed(
            qualifyingSeconds: agrees ? min(date.timeIntervalSince(enteredAt), monotonic) : monotonic,
            wallClockAgrees: agrees
        )
    }
}

/// A reading's boot against a visit's. A wall-clock step moves `kern.boottime` by the same amount,
/// so a different boot time does not prove a reboot; and a later boot's uptime can overtake the
/// visit's, so uptime does not prove the same boot either.
enum GeofenceBootRelation: Equatable, Sendable {
    /// The same boot time, and uptime no earlier than the record.
    case same
    /// A different boot time, and uptime no earlier than the record: a reboot, or a wall-clock
    /// step on the same boot. Nothing is measured across it.
    case ambiguous
    /// Uptime behind the record: only a later boot reads that.
    case knownOther
}

/// How long a visit has lasted up to some event.
struct GeofenceVisitElapsed: Equatable, Sendable {
    /// Time no wall-clock step can lengthen: the uptime since the visit was recorded, and while
    /// the wall clock agrees, no more than the wall time since the entry either.
    let qualifyingSeconds: TimeInterval
    /// The entry date and the event date are on one wall-clock timeline. When false, neither the
    /// entry nor a duration measured from it is reportable.
    let wallClockAgrees: Bool

    /// A microsecond of slack: a persisted date comes back up to one ulp (~1.2e-7 s) off, as
    /// `.secondsSince1970` rounds converting out of and back into the reference epoch, so a stay of
    /// exactly the threshold can read a hair short. The slack absorbs that and admits no fraction
    /// anyone could observe.
    func reaches(_ thresholdSeconds: Int) -> Bool {
        qualifyingSeconds + 0.000_001 >= TimeInterval(thresholdSeconds)
    }
}
