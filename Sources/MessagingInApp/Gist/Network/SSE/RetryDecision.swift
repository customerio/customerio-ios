import Foundation

/// Represents decisions made by SseRetryHelper about retry behavior.
/// This is emitted to the connection manager via an AsyncStream.
/// All delays are handled inside SseRetryHelper, so only RetryNow or failure cases are emitted.
/// Corresponds to Android's `RetryDecision` sealed class.
enum RetryDecision: Equatable {
    /// Retry now (all delays have been handled by SseRetryHelper)
    /// - Parameter attemptCount: The current retry attempt number (1-based)
    case retryNow(attemptCount: Int)

    /// Maximum retries reached, fallback to polling
    case maxRetriesReached

    /// Non-retryable error, fallback to polling
    case retryNotPossible
}
