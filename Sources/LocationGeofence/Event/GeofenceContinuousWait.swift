import Foundation

/// Waits measured on continuous time, the timeline `SystemGeofenceClock` reads uptime on, which keeps
/// counting while the device sleeps. `Task.sleep(nanoseconds:)` may count only awake time, so a wait it
/// measures can end long after a deadline computed on that timeline. A wait here still only resumes a
/// task, which runs only while iOS runs the app: it is not an OS execution deadline.
enum GeofenceContinuousWait {
    /// A wait of the given nanoseconds of continuous time, or nil where the OS has none (before iOS 16).
    /// For a caller an awake-time wait would break, such as the pending-dwell session, whose lease caps
    /// are continuous. Throws `CancellationError` once its task is cancelled, as `Task.sleep` does.
    static var continuous: (@Sendable (UInt64) async throws -> Void)? {
        guard #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) else { return nil }
        return { try await GeofenceContinuousWait.sleepContinuously(nanoseconds: $0) }
    }

    /// Continuous where available, else `Task.sleep(nanoseconds:)`. For a caller a late wake only delays,
    /// such as an evidence deadline, which still requests fresh proof when it fires.
    static func preferringContinuous(nanoseconds: UInt64) async throws {
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
            try await sleepContinuously(nanoseconds: nanoseconds)
        } else {
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    }

    @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
    private static func sleepContinuously(nanoseconds: UInt64) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .nanoseconds(Int64(clamping: nanoseconds)))
        try await Task.sleep(until: deadline, clock: clock)
    }
}
