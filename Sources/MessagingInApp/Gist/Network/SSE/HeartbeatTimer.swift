import CioInternalCommon
import Foundation

/// Heartbeat timer that monitors server heartbeats and emits timeout events
/// when the server stops sending heartbeats within the expected timeframe.
/// Corresponds to Android's `HeartbeatTimer` class.
actor HeartbeatTimer {
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
    private var onTimeout: (@Sendable () async -> Void)?
    private var currentTimerTask: Task<Void, Never>?

    /// Creates a HeartbeatTimer
    /// - Parameter logger: Logger for debug output
    init(logger: Logger) {
        self.logger = logger
        self.onTimeout = nil
    }

    /// Sets the timeout callback. Must be called before starting the timer.
    /// - Parameter callback: Callback invoked when the heartbeat timer expires without being reset
    func setCallback(_ callback: @escaping @Sendable () async -> Void) {
        onTimeout = callback
    }

    /// Starts the heartbeat timer with the specified timeout.
    ///
    /// If a timer is already running, it will be cancelled and replaced with the new timer.
    /// This is the expected behavior when receiving heartbeat events from the server.
    ///
    /// - Parameter timeoutSeconds: Timeout in seconds after which the timer will expire
    func startTimer(timeoutSeconds: TimeInterval) {
        // Cancel existing timer if running
        if currentTimerTask != nil {
            logger.logWithModuleTag("[HeartbeatTimer] Cancelling previous timer", level: .debug)
            currentTimerTask?.cancel()
        }

        // Clamp timeout to valid range to prevent overflow when converting to nanoseconds
        let clampedTimeout = min(max(timeoutSeconds, 0), Self.maxTimeoutSeconds)
        let nanoseconds = UInt64(clampedTimeout * 1000000000)

        logger.logWithModuleTag("[HeartbeatTimer] Starting timer with \(clampedTimeout)s timeout", level: .debug)

        // Use var so the closure captures by reference - by the time the Task body
        // executes, newTask will be assigned (Task body runs asynchronously)
        var newTask: Task<Void, Never>?

        newTask = Task { [weak self] in
            // Capture the task reference for later comparison
            guard let task = newTask else { return }

            do {
                await self?.logTimerWaiting(timeoutSeconds: clampedTimeout)

                // Task.sleep with nanoseconds required for iOS 13+ compatibility
                try await Task.sleep(nanoseconds: nanoseconds)

                // Check cancellation after sleep completes
                if Task.isCancelled {
                    await self?.logTimerCancelledAfterSleep()
                    return
                }

                // Timer expired - pass task reference to verify it's still current
                await self?.handleTimerExpired(task: task, timeoutSeconds: clampedTimeout)
            } catch is CancellationError {
                // Task was cancelled during sleep - expected behavior
                await self?.logTimerCancelledDuringSleep()
                return
            } catch {
                // Unexpected error - log but don't crash
                await self?.logUnexpectedError(error)
            }
        }

        currentTimerTask = newTask
    }

    /// Resets the heartbeat timer.
    /// Cancels any running timer without triggering the timeout callback.
    /// Should be called when connection is stopped or fails.
    func reset() {
        if currentTimerTask != nil {
            logger.logWithModuleTag("[HeartbeatTimer] Reset called - cancelling active timer", level: .debug)
            currentTimerTask?.cancel()
            currentTimerTask = nil
        } else {
            logger.logWithModuleTag("[HeartbeatTimer] Reset called - no active timer", level: .debug)
        }
    }

    // MARK: - Private Actor-Isolated Logging Methods

    private func logTimerWaiting(timeoutSeconds: TimeInterval) {
        logger.logWithModuleTag("[HeartbeatTimer] Timer waiting for \(timeoutSeconds)s...", level: .debug)
    }

    private func logTimerCancelledAfterSleep() {
        logger.logWithModuleTag("[HeartbeatTimer] Timer cancelled (detected after sleep)", level: .debug)
    }

    private func logTimerCancelledDuringSleep() {
        logger.logWithModuleTag("[HeartbeatTimer] Timer cancelled (during sleep)", level: .debug)
    }

    private func handleTimerExpired(task: Task<Void, Never>, timeoutSeconds: TimeInterval) async {
        // Only proceed if this is still the current timer (guards against race condition
        // where a new timer was started before this callback executed)
        guard currentTimerTask == task else {
            logger.logWithModuleTag("[HeartbeatTimer] Stale timer expired, ignoring (new timer already started)", level: .debug)
            return
        }

        // Clear the timer to reflect "no active timer" state
        currentTimerTask = nil

        logger.logWithModuleTag("[HeartbeatTimer] ⚠️ Timer EXPIRED after \(timeoutSeconds)s - triggering timeout callback", level: .error)
        await onTimeout?()
        logger.logWithModuleTag("[HeartbeatTimer] Timeout callback completed", level: .debug)
    }

    private func logUnexpectedError(_ error: Error) {
        logger.logWithModuleTag("[HeartbeatTimer] Unexpected error: \(error.localizedDescription)", level: .error)
    }
}
