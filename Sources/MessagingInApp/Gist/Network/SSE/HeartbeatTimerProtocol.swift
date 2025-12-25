import CioInternalCommon
import Foundation

/// Protocol for heartbeat timer to enable testing with mocks.
/// Abstracts timer functionality so `SseConnectionManager` can be tested
/// without real timing delays.
protocol HeartbeatTimerProtocol: AutoMockable {
    /// Sets the timeout callback. The callback receives the connection generation ID.
    /// - Parameter callback: Callback invoked when the heartbeat timer expires, with the generation ID
    func setCallback(_ callback: @escaping (UInt64) async -> Void) async

    /// Starts the heartbeat timer with the specified timeout for a specific connection generation.
    /// If a timer is already running, it will be cancelled and replaced with the new timer.
    /// - Parameters:
    ///   - timeoutSeconds: Timeout in seconds after which the timer will expire
    ///   - generation: The connection generation this timer is for
    func startTimer(timeoutSeconds: TimeInterval, generation: UInt64) async

    /// Resets the heartbeat timer for a specific generation.
    /// Only cancels the timer if the generation matches the active one.
    /// - Parameter generation: The connection generation to reset
    func reset(generation: UInt64) async
}
