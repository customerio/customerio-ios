@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import SharedTests

/// A `GeofenceClock` a test moves by hand. `advance` moves both clocks, as real time does;
/// `stepWall` moves only the wall clock, as a time change does; `reboot` starts a new boot.
final class ManualGeofenceClock: GeofenceClock, @unchecked Sendable {
    var wall: Date
    var uptime: TimeInterval
    var boot: GeofenceBootIdentity

    init(
        wall: Date = Date(timeIntervalSince1970: 1000000),
        uptime: TimeInterval = 10000,
        boot: GeofenceBootIdentity = GeofenceBootIdentity(bootTime: 500000, processToken: nil)
    ) {
        self.wall = wall
        self.uptime = uptime
        self.boot = boot
    }

    func read() -> GeofenceClockReading {
        GeofenceClockReading(wall: wall, uptime: uptime, boot: boot)
    }

    func advance(_ seconds: TimeInterval) {
        wall = wall.addingTimeInterval(seconds)
        uptime += seconds
    }

    /// Moves real time forward until the wall clock reads `date`; never backward.
    func advance(to date: Date) {
        advance(max(0, date.timeIntervalSince(wall)))
    }

    func stepWall(_ seconds: TimeInterval) {
        wall = wall.addingTimeInterval(seconds)
    }

    /// The device restarts `secondsLater` after the current wall time: uptime starts over.
    func reboot(secondsLater: TimeInterval = 60, uptimeAfterBoot: TimeInterval = 30) {
        wall = wall.addingTimeInterval(secondsLater)
        uptime = uptimeAfterBoot
        boot = GeofenceBootIdentity(bootTime: wall.timeIntervalSince1970 - uptimeAfterBoot, processToken: nil)
    }
}

/// A `GeofenceClock` on a `DateUtilStub`'s virtual time: one boot, with uptime moving exactly as
/// the stub's wall time does.
final class DateUtilGeofenceClock: GeofenceClock, @unchecked Sendable {
    private let dateUtil: DateUtilStub
    private static let boot = GeofenceBootIdentity(bootTime: 0, processToken: nil)

    init(dateUtil: DateUtilStub) {
        self.dateUtil = dateUtil
    }

    func read() -> GeofenceClockReading {
        let wall = dateUtil.givenNow
        return GeofenceClockReading(wall: wall, uptime: wall.timeIntervalSince1970, boot: Self.boot)
    }
}
