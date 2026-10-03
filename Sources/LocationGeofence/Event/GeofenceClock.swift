import Darwin
import Foundation

/// Reads the clocks a dwell visit is timed against: the wall clock its events are dated by, and a
/// monotonic clock no wall-clock change can move.
protocol GeofenceClock {
    /// Both clocks, read together, and the boot they belong to.
    func read() -> GeofenceClockReading
}

/// One reading of `GeofenceClock`.
struct GeofenceClockReading: Equatable, Sendable {
    let wall: Date
    /// Seconds of continuous uptime: counts through sleep, restarts at boot, and is never moved by
    /// a wall-clock change.
    let uptime: TimeInterval
    let boot: GeofenceBootIdentity

    /// Wall time minus uptime. Constant while the wall clock keeps step with uptime; a later
    /// reading on the same boot with a different offset saw the wall clock step.
    var wallOffset: TimeInterval {
        wall.timeIntervalSince1970 - uptime
    }
}

/// The boot a reading was taken on. Uptime from different boots is not comparable.
struct GeofenceBootIdentity: Codable, Equatable, Sendable {
    /// `kern.boottime`, seconds since 1970. Nil when it could not be read.
    let bootTime: TimeInterval?
    /// Set only when `bootTime` could not be read: unique to the process, so a visit recorded
    /// under it never outlives the process that recorded it.
    let processToken: String?

    /// Whether both identities name the same boot. Boot times a little apart still match:
    /// `kern.boottime` is microsecond-precise but may be nudged by time sync. Two unreadable boot
    /// times match only within one process.
    func isSameBoot(as other: GeofenceBootIdentity) -> Bool {
        if let bootTime, let otherBootTime = other.bootTime {
            return abs(bootTime - otherBootTime) <= Self.bootTimeTolerance
        }
        guard let processToken else { return false }
        return processToken == other.processToken
    }

    private static let bootTimeTolerance: TimeInterval = 1
}

/// `mach_continuous_time` and `kern.boottime`, both available on every supported iOS version.
/// Declared in the privacy manifest under system boot time (35F9.1): readings stay on device and
/// only order and measure the SDK's own events.
struct SystemGeofenceClock: GeofenceClock {
    func read() -> GeofenceClockReading {
        GeofenceClockReading(wall: Date(), uptime: Self.continuousUptime(), boot: Self.boot)
    }

    /// Read once: a process never spans a reboot.
    private static let boot: GeofenceBootIdentity = {
        if let bootTime = readBootTime() {
            return GeofenceBootIdentity(bootTime: bootTime, processToken: nil)
        }
        return GeofenceBootIdentity(bootTime: nil, processToken: UUID().uuidString)
    }()

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private static func continuousUptime() -> TimeInterval {
        let ticks = Double(mach_continuous_time())
        let nanoseconds = ticks * Double(timebase.numer) / Double(max(timebase.denom, 1))
        return nanoseconds / 1000000000
    }

    private static func readBootTime() -> TimeInterval? {
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctl(&mib, u_int(mib.count), &bootTime, &size, nil, 0) == 0, bootTime.tv_sec > 0 else {
            return nil
        }
        return TimeInterval(bootTime.tv_sec) + TimeInterval(bootTime.tv_usec) / 1000000
    }
}
