@testable import CioLocationGeofence
import Foundation

extension GeofenceVisitTiming {
    /// Timing for a visit `clock` recorded at its entry `secondsAgo`, on the clock's current boot.
    static func recorded(secondsAgo: TimeInterval = 0, on clock: GeofenceClock = SystemGeofenceClock()) -> GeofenceVisitTiming {
        let now = clock.read()
        let then = GeofenceClockReading(
            wall: now.wall.addingTimeInterval(-secondsAgo), uptime: now.uptime - secondsAgo, boot: now.boot
        )
        return GeofenceVisitTiming(enteredAt: then.wall, recordedAt: then)
    }
}
