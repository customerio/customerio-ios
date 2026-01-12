import CioInternalCommon
import Foundation

// sourcery: InjectRegisterShared = "SseRetryHelperProtocol"
/// Manages retry logic for SSE connections.
///
/// This actor handles retry decision-making separately from the main connection manager.
/// It tracks retry attempts and emits decisions via an AsyncStream to the connection manager.
/// All delays and waiting happen inside this helper.
///
/// Uses a connection generation ID to ensure retry operations only affect the correct
/// connection, preventing stale retries from triggering on new connections.
///
/// Corresponds to Android's `SseRetryHelper` class.
actor SseRetryHelper: SseRetryHelperProtocol {
    /// Maximum number of retry attempts before falling back to polling
    static let maxRetryCount = 3

    /// Delay between retry attempts (in seconds) - first retry is immediate
    static let retryDelaySeconds: TimeInterval = 5.0

    private let logger: Logger
    private let sleeper: Sleeper
    private var retryCount = 0
    private var retryTask: Task<Void, Never>?
    private var activeGeneration: UInt64 = 0

    // AsyncStream continuation for emitting retry decisions
    // Optional because stream is created fresh for each connection cycle
    private var continuation: AsyncStream<(RetryDecision, UInt64)>.Continuation?

    init(logger: Logger, sleeper: Sleeper = RealSleeper()) {
        self.logger = logger
        self.sleeper = sleeper
        logger.logWithModuleTag("[SseRetryHelper] Initialized", level: .debug)
    }

    /// Creates a new retry decision stream for this connection cycle.
    /// Any previous stream is finished (causes its iterator to exit cleanly).
    /// - Returns: A new AsyncStream that will emit retry decisions
    func createNewRetryStream() async -> AsyncStream<(RetryDecision, UInt64)> {
        // Finish old stream to clean up any lingering iterators
        continuation?.finish()

        let (stream, cont) = AsyncStreamBackport.makeStream(of: (RetryDecision, UInt64).self)
        continuation = cont

        logger.logWithModuleTag("[SseRetryHelper] Created new retry stream", level: .debug)
        return stream
    }

    /// Sets the active connection generation.
    /// Called when a new connection starts to reset retry state for the new generation.
    ///
    /// - Parameter generation: The new connection generation
    func setActiveGeneration(_ generation: UInt64) {
        logger.logWithModuleTag("[SseRetryHelper] Setting active generation to \(generation)", level: .debug)
        activeGeneration = generation
        retryTask?.cancel()
        retryTask = nil
        retryCount = 0
    }

    /// Schedules a retry for the given error and connection generation.
    /// Only processes if the generation matches the active one.
    ///
    /// - Parameters:
    ///   - error: The error that caused the connection failure
    ///   - generation: The connection generation this retry is for
    func scheduleRetry(error: SseError, generation: UInt64) {
        guard generation == activeGeneration else {
            logger.logWithModuleTag("[SseRetryHelper] Ignoring retry for stale generation \(generation) (active: \(activeGeneration))", level: .debug)
            return
        }

        if error.shouldRetry {
            attemptRetry(generation: generation)
        } else {
            logger.logWithModuleTag("[SseRetryHelper] Non-retryable error - falling back to polling", level: .info)
            emitRetryDecision(.retryNotPossible, generation: generation)
        }
    }

    /// Resets retry state for a specific generation.
    /// Only resets if the generation matches the active one.
    ///
    /// - Parameter generation: The connection generation to reset
    func resetRetryState(generation: UInt64) {
        guard generation == activeGeneration else {
            logger.logWithModuleTag("[SseRetryHelper] Skipping reset - generation mismatch (requested \(generation) vs active \(activeGeneration))", level: .debug)
            return
        }

        retryTask?.cancel()
        retryTask = nil
        retryCount = 0
        logger.logWithModuleTag("[SseRetryHelper] Retry state reset (generation \(generation))", level: .debug)
    }

    // MARK: - Private Methods

    private func attemptRetry(generation: UInt64) {
        if retryCount >= Self.maxRetryCount {
            logger.logWithModuleTag("[SseRetryHelper] Max retries exceeded (\(retryCount)/\(Self.maxRetryCount)) - falling back to polling", level: .error)
            emitRetryDecision(.maxRetriesReached, generation: generation)
            return
        }

        retryCount += 1
        let currentAttempt = retryCount

        // First retry - emit immediately (no delay)
        if currentAttempt == 1 {
            logger.logWithModuleTag("[SseRetryHelper] Scheduling immediate retry (attempt \(currentAttempt)/\(Self.maxRetryCount), generation \(generation))", level: .info)
            emitRetryDecision(.retryNow(attemptCount: currentAttempt), generation: generation)
            return
        }

        // Subsequent retries - schedule with delay
        logger.logWithModuleTag("[SseRetryHelper] Scheduling delayed retry in \(Self.retryDelaySeconds)s (attempt \(currentAttempt)/\(Self.maxRetryCount), generation \(generation))", level: .info)

        // Cancel any existing retry task
        retryTask?.cancel()

        // Capture sleeper reference for the task
        let sleeper = self.sleeper

        retryTask = Task { [weak self, currentAttempt, generation] in
            do {
                await self?.logger.logWithModuleTag("[SseRetryHelper] ⏳ Waiting \(Self.retryDelaySeconds)s before retry attempt \(currentAttempt)/\(Self.maxRetryCount)...", level: .info)

                // Use injected sleeper for delay (enables fast tests)
                try await sleeper.sleep(seconds: Self.retryDelaySeconds)

                // Check if task was cancelled during sleep
                guard !Task.isCancelled else {
                    await self?.logger.logWithModuleTag("[SseRetryHelper] Retry cancelled (generation \(generation))", level: .debug)
                    return
                }

                // Emit with generation verification
                await self?.emitIfStillActive(decision: .retryNow(attemptCount: currentAttempt), generation: generation)
            } catch is CancellationError {
                await self?.logger.logWithModuleTag("[SseRetryHelper] Retry cancelled (generation \(generation))", level: .debug)
            } catch {
                await self?.logger.logWithModuleTag("[SseRetryHelper] Unexpected error during retry delay: \(error.localizedDescription)", level: .error)
            }
        }
    }

    private func emitIfStillActive(decision: RetryDecision, generation: UInt64) {
        guard generation == activeGeneration else {
            logger.logWithModuleTag("[SseRetryHelper] Skipping emit - generation mismatch (requested \(generation) vs active \(activeGeneration))", level: .debug)
            return
        }

        logger.logWithModuleTag("[SseRetryHelper] Delay completed, emitting retry decision (generation \(generation))", level: .info)
        emitRetryDecision(decision, generation: generation)
    }

    private func emitRetryDecision(_ decision: RetryDecision, generation: UInt64) {
        guard let continuation = continuation else {
            logger.logWithModuleTag("[SseRetryHelper] Warning: No active stream to emit decision", level: .error)
            return
        }
        logger.logWithModuleTag("[SseRetryHelper] Emitting decision: \(decision) (generation \(generation))", level: .debug)
        continuation.yield((decision, generation))
    }
}
