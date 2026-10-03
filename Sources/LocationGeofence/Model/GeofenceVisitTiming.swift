import Foundation

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
        boot.isSameBoot(as: reading.boot) && reading.uptime >= recordedUptime
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

/// How long a visit has lasted up to some event.
struct GeofenceVisitElapsed: Equatable, Sendable {
    /// Time no wall-clock step can lengthen: the uptime since the visit was recorded, and while
    /// the wall clock agrees, no more than the wall time since the entry either.
    let qualifyingSeconds: TimeInterval
    /// The entry date and the event date are on one wall-clock timeline. When false, neither the
    /// entry nor a duration measured from it is reportable.
    let wallClockAgrees: Bool

    /// A microsecond of slack, for the same reason as `GeofenceDwellCoordinator.wholeSeconds`.
    func reaches(_ thresholdSeconds: Int) -> Bool {
        qualifyingSeconds + 0.000_001 >= TimeInterval(thresholdSeconds)
    }
}
