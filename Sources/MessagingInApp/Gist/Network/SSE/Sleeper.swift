import CioInternalCommon
import Foundation

/// Protocol for abstracting sleep/delay functionality.
/// Enables testing of time-dependent code without real delays.
protocol Sleeper: AutoMockable {
    /// Sleeps for the specified duration.
    /// - Parameter seconds: The number of seconds to sleep
    /// - Throws: CancellationError if the task is cancelled during sleep
    func sleep(seconds: TimeInterval) async throws
}

// sourcery: InjectRegisterShared = "Sleeper"
/// Production implementation of Sleeper using Task.sleep.
struct RealSleeper: Sleeper {
    func sleep(seconds: TimeInterval) async throws {
        let nanoseconds = UInt64(seconds * 1000000000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}
