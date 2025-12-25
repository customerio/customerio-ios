import CioInternalCommon
import Foundation

/// Protocol for SSE retry helper to enable testing with mocks.
/// Abstracts retry logic so `SseConnectionManager` can be tested
/// with controlled retry behavior.
protocol SseRetryHelperProtocol: AutoMockable {
    /// Stream of retry decisions emitted by the helper.
    /// Emits tuples of (decision, generation) so the manager can verify the generation is still active.
    var retryDecisionStream: AsyncStream<(RetryDecision, UInt64)> { get }

    /// Sets the active connection generation.
    /// Called when a new connection starts to reset retry state for the new generation.
    /// - Parameter generation: The new connection generation
    func setActiveGeneration(_ generation: UInt64) async

    /// Schedules a retry for the given error and connection generation.
    /// Only processes if the generation matches the active one.
    /// - Parameters:
    ///   - error: The error that caused the connection failure
    ///   - generation: The connection generation this retry is for
    func scheduleRetry(error: SseError, generation: UInt64) async

    /// Resets retry state for a specific generation.
    /// Only resets if the generation matches the active one.
    /// - Parameter generation: The connection generation to reset
    func resetRetryState(generation: UInt64) async
}
