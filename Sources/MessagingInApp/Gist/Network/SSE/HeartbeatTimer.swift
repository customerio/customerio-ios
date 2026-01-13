import CioInternalCommon
import Foundation

// sourcery: InjectRegisterShared = "HeartbeatTimerProtocol"
/// Heartbeat timer that monitors server heartbeats and emits timeout events
/// when the server stops sending heartbeats within the expected timeframe.
///
/// Uses a connection generation ID to ensure callbacks and resets only affect
/// the correct connection, preventing stale timeouts from triggering on new connections.
///
/// Corresponds to Android's `HeartbeatTimer` class.
actor HeartbeatTimer: HeartbeatTimerProtocol {
    /// Default heartbeat timeout in seconds (matches Android's DEFAULT_HEARTBEAT_TIMEOUT_MS / 1000)
    static let defaultHeartbeatTimeoutSeconds: TimeInterval = 30

    /// Buffer added to heartbeat timeout to account for network delays
    static let heartbeatBufferSeconds: TimeInterval = 5

    /// Initial timeout used when connection opens before receiving server heartbeat config
    static let initialTimeoutSeconds: TimeInterval = defaultHeartbeatTimeoutSeconds + heartbeatBufferSeconds

    /// Maximum timeout in seconds to prevent overflow when converting to nanoseconds
    /// UInt64.max nanoseconds ≈ 584 years, but we cap at 1 hour for practical purposes
    private static let maxTimeoutSeconds: TimeInterval = 3600

    private let logger: Logger
    private var onTimeout: ((UInt64) async -> Void)?
    private var currentTimerTask: Task<Void, Never>?
    private var activeGeneration: UInt64 = 0

    /// Creates a HeartbeatTimer
    /// - Parameter logger: Logger for debug output
    init(logger: Logger) {
        self.logger = logger
    }

    /// Sets the timeout callback. The callback receives the connection generation ID.
    /// - Parameter callback: Callback invoked when the heartbeat timer expires, with the generation ID
    func setCallback(_ callback: @escaping (UInt64) async -> Void) {
        onTimeout = callback
    }

    /// Starts the heartbeat timer with the specified timeout for a specific connection generation.
    ///
    /// If a timer is already running, it will be cancelled and replaced with the new timer.
    /// This is the expected behavior when receiving heartbeat events from the server.
    ///
    /// - Parameters:
    ///   - timeoutSeconds: Timeout in seconds after which the timer will expire
    ///   - generation: The connection generation this timer is for
    func startTimer(timeoutSeconds: TimeInterval, generation: UInt64) {
        // Cancel existing timer if running
        if currentTimerTask != nil {
            logger.logWithModuleTag("[HeartbeatTimer] Cancelling previous timer", level: .debug)
            currentTimerTask?.cancel()
        }

        activeGeneration = generation

        // Clamp timeout to valid range to prevent overflow when converting to nanoseconds
        let clampedTimeout = min(max(timeoutSeconds, 0), Self.maxTimeoutSeconds)
        let nanoseconds = UInt64(clampedTimeout * 1000000000)

        logger.logWithModuleTag("[HeartbeatTimer] Starting timer with \(clampedTimeout)s timeout (generation \(generation))", level: .debug)

        currentTimerTask = Task { [weak self, generation, clampedTimeout] in
            do {
                // Task.sleep with nanoseconds required for iOS 13+ compatibility
                try await Task.sleep(nanoseconds: nanoseconds)

                // Check cancellation after sleep completes
                guard !Task.isCancelled else {
                    await self?.logTimerCancelled(generation: generation)
                    return
                }

                // Fire callback with generation - manager will verify it's still current
                await self?.fireCallbackIfActive(generation: generation, timeoutSeconds: clampedTimeout)
            } catch is CancellationError {
                // Task was cancelled during sleep - expected behavior
                await self?.logTimerCancelled(generation: generation)
            } catch {
                // Unexpected error - log but don't crash
                await self?.logUnexpectedError(error)
            }
        }
    }

    /// Resets the heartbeat timer for a specific generation.
    /// Only cancels the timer if the generation matches the active one.
    ///
    /// - Parameter generation: The connection generation to reset
    func reset(generation: UInt64) {
        guard generation == activeGeneration else {
            logger.logWithModuleTag("[HeartbeatTimer] Skipping reset - generation mismatch (requested \(generation) vs active \(activeGeneration))", level: .debug)
            return
        }

        if currentTimerTask != nil {
            logger.logWithModuleTag("[HeartbeatTimer] Reset called - cancelling active timer (generation \(generation))", level: .debug)
            currentTimerTask?.cancel()
            currentTimerTask = nil
        } else {
            logger.logWithModuleTag("[HeartbeatTimer] Reset called - no active timer (generation \(generation))", level: .debug)
        }
    }

    // MARK: - Private Methods

    private func fireCallbackIfActive(generation: UInt64, timeoutSeconds: TimeInterval) async {
        // Verify this timer is still for the active generation
        guard generation == activeGeneration else {
            logger.logWithModuleTag("[HeartbeatTimer] Stale timer expired (generation \(generation) vs active \(activeGeneration)), ignoring", level: .debug)
            return
        }

        logger.logWithModuleTag("[HeartbeatTimer] ⚠️ Timer EXPIRED after \(timeoutSeconds)s - triggering timeout callback (generation \(generation))", level: .error)
        await onTimeout?(generation)
        logger.logWithModuleTag("[HeartbeatTimer] Timeout callback completed", level: .debug)
    }

    private func logTimerCancelled(generation: UInt64) {
        logger.logWithModuleTag("[HeartbeatTimer] Timer cancelled (generation \(generation))", level: .debug)
    }

    private func logUnexpectedError(_ error: Error) {
        logger.logWithModuleTag("[HeartbeatTimer] Unexpected error: \(error.localizedDescription)", level: .error)
    }
}
