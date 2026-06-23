import CioInternalCommon
import Foundation

/// Exponential-backoff configuration for templates/branding fetches.
struct InboxRetryPolicy {
    /// Base delay before the first retry (seconds).
    let baseDelay: TimeInterval
    /// Multiplier applied to the delay after each failed attempt.
    let multiplier: Double
    /// Maximum number of attempts (initial try + retries).
    let maxAttempts: Int

    static let `default` = InboxRetryPolicy(baseDelay: 0.5, multiplier: 2.0, maxAttempts: 3)

    /// Delay before the retry that follows `attemptIndex` (0-based: 0 == delay after first attempt).
    func delay(afterAttempt attemptIndex: Int) -> TimeInterval {
        baseDelay * pow(multiplier, Double(attemptIndex))
    }
}

/// Runs an async operation with exponential-backoff retry.
///
/// Each attempt carries the caller's per-attempt timeout (the operation itself is responsible
/// for the 5s `URLRequest` timeout). Sleep between attempts is delegated to an injected `Sleeper`
/// so backoff is testable without real delays.
struct InboxFetchRetrier {
    private let policy: InboxRetryPolicy
    private let sleeper: Sleeper
    private let logger: Logger

    init(policy: InboxRetryPolicy = .default, sleeper: Sleeper, logger: Logger) {
        self.policy = policy
        self.sleeper = sleeper
        self.logger = logger
    }

    /// Attempts `operation` up to `policy.maxAttempts` times, sleeping with exponential backoff
    /// between failures.
    /// - Returns: the successful value.
    /// - Throws: the last error if all attempts fail.
    func run<T>(label: String, operation: @escaping () async throws -> T) async throws -> T {
        var lastError: Error = InboxNetworkError.noResponse
        for attempt in 0 ..< policy.maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                let isLastAttempt = attempt == policy.maxAttempts - 1
                logger.logWithModuleTag(
                    "Inbox fetch '\(label)' attempt \(attempt + 1)/\(policy.maxAttempts) failed: \(error)",
                    level: isLastAttempt ? .error : .debug
                )
                if isLastAttempt { break }
                let delay = policy.delay(afterAttempt: attempt)
                try? await sleeper.sleep(seconds: delay)
            }
        }
        throw lastError
    }
}
