// swiftlint:disable file_length type_body_length
import CioInternalCommon
import Foundation

/// Protocol for SSE connection management, enabling testability.
protocol SseConnectionManagerProtocol: AutoMockable {
    /// Starts an SSE connection to the queue consumer API.
    func startConnection() async

    /// Stops the current SSE connection.
    func stopConnection() async
}

// sourcery: InjectRegisterShared = "SseConnectionManagerProtocol"
// sourcery: InjectSingleton
/// Manages SSE (Server-Sent Events) connections for real-time in-app message delivery.
/// Handles connection lifecycle, event parsing, and automatic retry behavior on connection failures.
///
/// Corresponds to Android's `SseConnectionManager` class.
///
/// ## Connection Generation
///
/// This implementation uses a connection generation ID to eliminate race conditions.
/// Each new connection attempt increments the generation counter. All cleanup operations,
/// callbacks, and event handlers carry this generation ID and are ignored if it doesn't
/// match the current active connection. This prevents:
/// - `stopConnection()` cleanup from killing a new connection that started during await
/// - Stale heartbeat timeouts from triggering on new connections
/// - Stale retry decisions from affecting new connections
///
/// ## Connection state transitions:
/// - DISCONNECTED -> CONNECTING (startConnection)
/// - CONNECTING -> CONNECTED (ConnectionOpenEvent/CONNECTED event from server)
/// - CONNECTED -> DISCONNECTING (stopConnection)
/// - CONNECTING/CONNECTED -> DISCONNECTED (ConnectionFailedEvent/ConnectionClosedEvent from SseService)
/// - DISCONNECTING -> DISCONNECTED (stopConnection completes, or ConnectionClosedEvent if disconnect() was called)
///
/// ## Task lifecycle:
///
/// **streamTask (Connection Event Collector)**:
/// - Starts: When `startConnection()` is called
/// - Purpose: Collects SSE events from `SseService` and processes them
/// - Cancelled: In `stopConnection()` or when starting a new connection attempt
///
/// **retryTask (Retry Decision Collector)**:
/// - Starts: When `subscribeToRetryDecisions()` is called (during `startConnection()`)
/// - Purpose: Collects retry decisions from `SseRetryHelper` and acts on them (start connection, fallback to polling)
/// - Cancelled: In `stopConnection()` when explicitly stopping the connection (matches Android's behavior)
///
/// **HeartbeatTimer**:
/// - Started: In `setupSuccessfulConnection()` when connection is confirmed (ConnectionOpenEvent/CONNECTED event)
/// - Reset: In `handleConnectionFailure()`, `cleanupForReconnect()`, `handleCompleteFailure()`, and `ConnectionClosedEvent` handler
/// - Purpose: Monitors server heartbeats and triggers timeout if no heartbeat received within the timeout period
actor SseConnectionManager: SseConnectionManagerProtocol {
    private let logger: Logger
    private let inAppMessageManager: InAppMessageManager
    private let sseService: SseServiceProtocol
    private let retryHelper: SseRetryHelperProtocol
    private let heartbeatTimer: HeartbeatTimerProtocol

    /// The current connection generation. Incremented each time a new connection starts.
    /// Used to prevent stale operations from affecting new connections.
    private var activeConnectionGeneration: UInt64 = 0

    private var connectionState: SseConnectionState = .disconnected
    private var streamTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?

    init(
        logger: Logger,
        inAppMessageManager: InAppMessageManager,
        sseService: SseServiceProtocol,
        retryHelper: SseRetryHelperProtocol,
        heartbeatTimer: HeartbeatTimerProtocol
    ) {
        self.logger = logger
        self.inAppMessageManager = inAppMessageManager
        self.sseService = sseService
        self.retryHelper = retryHelper
        self.heartbeatTimer = heartbeatTimer

        logger.logWithModuleTag("SseConnectionManager initialized", level: .debug)
    }

    /// Sets up the heartbeat timer callback.
    /// Called automatically by startConnection() - idempotent, safe to call multiple times.
    private var heartbeatCallbackSet = false
    private func setHeartbeatCallback() async {
        guard !heartbeatCallbackSet else { return }
        heartbeatCallbackSet = true

        logger.logWithModuleTag("SSE Manager: Setting up heartbeat timeout callback", level: .debug)
        await heartbeatTimer.setCallback { [weak self] generation in
            guard let self = self else { return }
            await self.handleHeartbeatTimeout(generation: generation)
        }
    }

    // MARK: - Public API

    /// Starts an SSE connection to the queue consumer API.
    /// This method is idempotent - calling it multiple times while connected/connecting is safe.
    ///
    /// Fetches the current state from InAppMessageManager to establish the connection.
    /// Allows connection attempts from DISCONNECTING state - the old connection's event collection
    /// will be cancelled, so we won't receive disconnected events from the old connection.
    func startConnection() async {
        logger.logWithModuleTag("SSE Manager: startConnection called", level: .info)

        // Ensure heartbeat callback is set up (idempotent - safe to call multiple times)
        await setHeartbeatCallback()

        // Fetch current state from manager
        let state = await inAppMessageManager.state
        logger.logWithModuleTag("SSE Manager: useSse=\(state.useSse), userId=\(state.userId ?? "nil"), anonymousId=\(state.anonymousId ?? "nil")", level: .debug)

        // Check if already active
        if connectionState == .connecting || connectionState == .connected {
            logger.logWithModuleTag("SSE Manager: Connection already active (state: \(connectionState.description))", level: .debug)
            return
        }

        // Increment generation for new connection - this must happen BEFORE any await
        // so that stopConnection() captures the correct generation
        activeConnectionGeneration += 1
        let generation = activeConnectionGeneration

        logger.logWithModuleTag("SSE Manager: Starting connection (generation \(generation))", level: .info)

        // Cancel any existing stream task
        streamTask?.cancel()

        // Update state to connecting
        updateConnectionState(.connecting)

        // Set the active generation in retry helper
        await retryHelper.setActiveGeneration(generation)

        // Ensure retry decision collector is running with fresh stream
        await subscribeToRetryDecisions()

        // Start the connection
        var newTask: Task<Void, Never>?

        newTask = Task { [weak self, generation] in
            guard let self = self else { return }
            guard let task = newTask else { return }
            await self.executeConnectionAttempt(task: task, generation: generation)
        }

        streamTask = newTask
    }

    /// Stops the active SSE connection.
    /// This method is idempotent - calling it multiple times is safe.
    ///
    /// The cleanup operations include the connection generation, so they only affect
    /// the connection that was active when stopConnection() was called. If a new connection
    /// starts during the await points, it won't be affected by this cleanup.
    func stopConnection() async {
        // Capture the generation we're stopping BEFORE any state changes
        let stoppingGeneration = activeConnectionGeneration

        logger.logWithModuleTag("SSE Manager: stopConnection called (stopping generation \(stoppingGeneration))", level: .info)

        updateConnectionState(.disconnecting)

        // Cancel all tasks
        streamTask?.cancel()
        streamTask = nil
        retryTask?.cancel()
        retryTask = nil

        // Reset helpers with generation - they will ignore if generation doesn't match
        await retryHelper.resetRetryState(generation: stoppingGeneration)
        await heartbeatTimer.reset(generation: stoppingGeneration)
        await sseService.disconnect(connectionId: stoppingGeneration)

        // Only update state if still the same generation (no new connection started during awaits)
        guard activeConnectionGeneration == stoppingGeneration else {
            logger.logWithModuleTag("SSE Manager: New connection started during stop (gen \(activeConnectionGeneration)), skipping final state update", level: .debug)
            return
        }

        updateConnectionState(.disconnected)

        logger.logWithModuleTag("SSE Manager: Connection stopped", level: .info)
    }

    // MARK: - Connection Execution

    /// Executes the actual connection attempt and handles failures.
    /// - Parameters:
    ///   - task: The task reference for this connection attempt
    ///   - generation: The connection generation this attempt belongs to
    private func executeConnectionAttempt(task: Task<Void, Never>, generation: UInt64) async {
        // Verify generation is still current before connecting
        guard generation == activeConnectionGeneration else {
            logger.logWithModuleTag("SSE Manager: Stale connection attempt (generation \(generation) vs \(activeConnectionGeneration)), aborting", level: .debug)
            return
        }

        // Fetch current state from manager
        let state = await inAppMessageManager.state

        let eventStream = await sseService.connect(state: state, connectionId: generation)

        logger.logWithModuleTag("SSE Manager: Connected with connectionId \(generation)", level: .debug)

        // Process events from stream
        for await event in eventStream {
            // Check for cancellation before processing each event
            guard !Task.isCancelled else {
                logger.logWithModuleTag("SSE Manager: Connection task cancelled", level: .debug)
                return
            }

            // Verify generation is still current
            guard generation == activeConnectionGeneration else {
                logger.logWithModuleTag("SSE Manager: Event received for stale generation \(generation), ignoring", level: .debug)
                return
            }

            await handleEvent(event, generation: generation)
        }

        // Stream ended - pass task and generation reference to verify it's still current
        handleStreamEnded(task: task, generation: generation)
    }

    // MARK: - Event Handlers

    private func handleEvent(_ event: SseEvent, generation: UInt64) async {
        switch event {
        case .connectionOpen:
            await handleConnectionOpen(generation: generation)

        case .serverEvent(let serverEvent):
            await handleServerEvent(serverEvent, generation: generation)

        case .connectionFailed(let error):
            await handleConnectionFailed(error, generation: generation)

        case .connectionClosed:
            await handleConnectionClosed(generation: generation)
        }
    }

    private func handleStreamEnded(task: Task<Void, Never>, generation: UInt64) {
        // Only proceed if this is still the current stream task and generation
        guard streamTask == task, generation == activeConnectionGeneration else {
            logger.logWithModuleTag("SSE Manager: Stale stream ended (gen \(generation) vs \(activeConnectionGeneration)), ignoring", level: .debug)
            return
        }

        logger.logWithModuleTag("SSE Manager: Event stream ended normally", level: .info)

        // Defensive cleanup - ensure timer is reset and state is correct
        Task {
            await heartbeatTimer.reset(generation: generation)
        }
        updateConnectionState(.disconnected)

        streamTask = nil
    }

    // MARK: - Connection Lifecycle Handlers

    private func handleConnectionOpen(generation: UInt64) async {
        guard generation == activeConnectionGeneration else { return }

        logger.logWithModuleTag("SSE Manager: ✓ Connection opened (generation \(generation))", level: .info)
        await setupSuccessfulConnection(generation: generation)
    }

    private func handleConnectionClosed(generation: UInt64) async {
        guard generation == activeConnectionGeneration else { return }

        logger.logWithModuleTag("SSE Manager: Connection closed", level: .info)

        // Check if this is an unexpected close (still in connected/connecting state)
        // vs a close following an error (already in disconnected state from handleConnectionFailed)
        // vs an intentional stop (in disconnecting state from stopConnection)
        //
        // On iOS, URLSession reports server-initiated closes as didCompleteWithError(error: nil),
        // which triggers onClosed() without going through the error handler. This differs from
        // Android/OkHttp where such closes throw StreamClosedByServerException and go through
        // the error path. We need to treat unexpected closes as retriable errors to match
        // Android's behavior.
        let wasUnexpectedClose = connectionState == .connecting || connectionState == .connected

        // Reset heartbeat timer when connection closes
        await heartbeatTimer.reset(generation: generation)

        updateConnectionState(.disconnected)

        // If connection closed unexpectedly (not following an error or intentional stop),
        // treat it as a retriable network error
        if wasUnexpectedClose {
            logger.logWithModuleTag("SSE Manager: ⚠️ Unexpected connection close - treating as retriable error", level: .info)
            let error = SseError.networkError(message: "Connection closed unexpectedly", underlyingError: nil)
            await retryHelper.scheduleRetry(error: error, generation: generation)
        }
    }

    private func handleConnectionFailed(_ error: SseError, generation: UInt64) async {
        // Verify generation is still current
        guard generation == activeConnectionGeneration else {
            logger.logWithModuleTag("SSE Manager: Ignoring failure for stale generation \(generation)", level: .debug)
            return
        }

        // Guard against duplicate failure handling for the same connection
        guard connectionState == .connecting || connectionState == .connected else {
            logger.logWithModuleTag("SSE Manager: Ignoring duplicate failure - already in \(connectionState.description) state", level: .debug)
            return
        }

        logger.logWithModuleTag("SSE Manager: ✗ Connection failed: \(error.message), retryable: \(error.shouldRetry)", level: .error)
        logger.logWithModuleTag("SSE Manager: Error type: \(error.errorType)", level: .debug)

        // Cleanup between retries
        updateConnectionState(.disconnected)
        await heartbeatTimer.reset(generation: generation)

        // Schedule retry (or fallback if non-retryable)
        logger.logWithModuleTag("SSE Manager: Requesting retry decision from helper...", level: .debug)
        await retryHelper.scheduleRetry(error: error, generation: generation)
    }

    // MARK: - Server Event Handlers

    private func handleServerEvent(_ event: ServerEvent, generation: UInt64) async {
        guard generation == activeConnectionGeneration else { return }

        logger.logWithModuleTag("SSE Manager: ← Server event '\(event.eventType)'", level: .info)
        logger.logWithModuleTag("SSE Manager: Event data: \(event.data.prefix(100))", level: .debug)

        switch event.eventType {
        case .connected:
            logger.logWithModuleTag("SSE Manager: ✓ Server acknowledged connection", level: .info)
            await setupSuccessfulConnection(generation: generation)

        case .heartbeat:
            await handleHeartbeatEvent(event, generation: generation)

        case .messages:
            handleMessagesEvent(event)

        case .inboxMessages:
            handleInboxMessagesEvent(event)

        case .ttlExceeded:
            logger.logWithModuleTag("SSE Manager: TTL exceeded - reconnecting", level: .info)
            await cleanupForReconnect(generation: generation)

            // Guard against task cancellation (e.g., if stopConnection() was called during cleanup)
            guard !Task.isCancelled else {
                logger.logWithModuleTag("SSE Manager: Task cancelled during TTL cleanup, skipping reconnection", level: .debug)
                return
            }

            // Reconnect (will fetch fresh state from manager)
            await startConnection()

        case .unknown:
            logger.logWithModuleTag("SSE Manager: Unknown server event type '\(event.rawEventType ?? "nil")', ignoring", level: .debug)
        }
    }

    private func handleHeartbeatEvent(_ event: ServerEvent, generation: UInt64) async {
        guard generation == activeConnectionGeneration else { return }

        // Use server-provided interval or default if parsing failed (nil for edge cases like empty data, malformed JSON)
        let heartbeatInterval = event.heartbeatIntervalSeconds ?? HeartbeatTimer.defaultHeartbeatTimeoutSeconds
        let timeoutWithBuffer = heartbeatInterval + HeartbeatTimer.heartbeatBufferSeconds

        logger.logWithModuleTag("SSE Manager: Heartbeat received (interval: \(heartbeatInterval)s, timeout: \(timeoutWithBuffer)s)", level: .debug)

        // Restart heartbeat timer with the parsed interval + buffer
        await heartbeatTimer.startTimer(timeoutSeconds: timeoutWithBuffer, generation: generation)
    }

    private func handleMessagesEvent(_ event: ServerEvent) {
        logger.logWithModuleTag("SSE Manager: Message event received", level: .info)

        guard let messages = event.messages, !messages.isEmpty else {
            logger.logWithModuleTag("SSE Manager: No messages in event or failed to parse", level: .debug)
            return
        }

        logger.logWithModuleTag("SSE Manager: ✓ Received \(messages.count) in-app message(s) from SSE", level: .info)

        // Dispatch to message queue processor (same as polling does)
        inAppMessageManager.dispatch(action: .processMessageQueue(messages: messages))
    }

    private func handleInboxMessagesEvent(_ event: ServerEvent) {
        logger.logWithModuleTag("SSE Manager: Inbox messages event received", level: .info)

        guard let inboxMessages = event.inboxMessages, !inboxMessages.isEmpty else {
            logger.logWithModuleTag("SSE Manager: No inbox messages in event or failed to parse", level: .debug)
            return
        }

        logger.logWithModuleTag("SSE Manager: ✓ Received \(inboxMessages.count) inbox message(s) from SSE", level: .info)

        // Dispatch to inbox message processor (same as polling does)
        inAppMessageManager.dispatch(action: .processInboxMessages(messages: inboxMessages))
    }

    // MARK: - Heartbeat Timeout Handler

    /// Handles heartbeat timeout - called when no heartbeat is received within the expected timeframe
    /// - Parameter generation: The connection generation this timeout is for
    private func handleHeartbeatTimeout(generation: UInt64) async {
        // Verify generation is still current
        guard generation == activeConnectionGeneration else {
            logger.logWithModuleTag("SSE Manager: Ignoring stale heartbeat timeout (gen \(generation) vs \(activeConnectionGeneration))", level: .debug)
            return
        }

        logger.logWithModuleTag("SSE Manager: ⚠️ Heartbeat timeout - triggering retry logic", level: .error)

        // Treat timeout as a retryable error
        await handleConnectionFailed(.timeoutError, generation: generation)
    }

    // MARK: - Retry Logic

    /// Sets up subscription to retry decisions from SseRetryHelper.
    /// Creates a fresh stream for each connection cycle to avoid AsyncStream exhaustion issues.
    private func subscribeToRetryDecisions() async {
        // Cancel existing retry task - it will exit when old stream is finished
        retryTask?.cancel()
        retryTask = nil

        logger.logWithModuleTag("SSE Manager: Setting up retry decision subscription", level: .debug)

        // Get FRESH stream - this also finishes any old stream, causing old iterators to exit
        let stream = await retryHelper.createNewRetryStream()

        retryTask = Task { [weak self] in
            guard let self = self else { return }

            await self.logger.logWithModuleTag("SSE Manager: Retry task started, iterating stream...", level: .debug)

            for await(decision, generation) in stream {
                await self.logger.logWithModuleTag("SSE Manager: Received retry decision: \(decision) (generation \(generation))", level: .debug)

                // Check for cancellation
                guard !Task.isCancelled else {
                    await self.logRetryCancelled()
                    return
                }

                await self.handleRetryDecision(decision, generation: generation)
            }

            await self.logger.logWithModuleTag("SSE Manager: Retry stream ended", level: .debug)
        }
    }

    private func handleRetryDecision(_ decision: RetryDecision, generation: UInt64) async {
        // Verify generation is still current
        guard generation == activeConnectionGeneration else {
            logger.logWithModuleTag("SSE Manager: Ignoring stale retry decision (gen \(generation) vs \(activeConnectionGeneration))", level: .debug)
            return
        }

        switch decision {
        case .retryNow(let attemptCount):
            logger.logWithModuleTag("SSE Manager: Retrying connection (attempt \(attemptCount)/\(SseRetryHelper.maxRetryCount))", level: .info)

            // Cancel existing stream task before retry
            streamTask?.cancel()
            streamTask = nil

            // Update state and start new connection (will fetch fresh state from manager)
            updateConnectionState(.connecting)

            // Start new connection attempt with same generation
            var newTask: Task<Void, Never>?

            newTask = Task { [weak self, generation] in
                guard let self = self else { return }
                guard let task = newTask else { return }
                await self.executeConnectionAttempt(task: task, generation: generation)
            }

            streamTask = newTask

        case .maxRetriesReached:
            logger.logWithModuleTag("SSE Manager: Max retries reached - falling back to polling", level: .error)
            await handleCompleteFailure(generation: generation)

        case .retryNotPossible:
            logger.logWithModuleTag("SSE Manager: Non-retryable error - falling back to polling", level: .error)
            await handleCompleteFailure(generation: generation)
        }
    }

    /// Handles complete failure: cleans up and falls back to polling.
    /// This is called when max retries are reached or error is non-retryable.
    private func handleCompleteFailure(generation: UInt64) async {
        guard generation == activeConnectionGeneration else { return }

        logger.logWithModuleTag("SSE Manager: Complete failure - falling back to polling", level: .error)

        // Cleanup on complete failure
        updateConnectionState(.disconnected)
        await heartbeatTimer.reset(generation: generation)
        await retryHelper.resetRetryState(generation: generation)

        // Re-check generation after await points before taking global action
        // (a new connection may have started during the cleanup awaits)
        guard generation == activeConnectionGeneration else {
            logger.logWithModuleTag("SSE Manager: New connection started during cleanup, skipping SSE disable", level: .debug)
            return
        }

        // Fallback to polling by disabling SSE
        inAppMessageManager.dispatch(action: .setSseEnabled(enabled: false))
    }

    /// Cleans up state before reconnecting (e.g., after TTL_EXCEEDED).
    /// Resets connection state, heartbeat timer, and retry state.
    private func cleanupForReconnect(generation: UInt64) async {
        guard generation == activeConnectionGeneration else { return }

        updateConnectionState(.disconnected)
        await heartbeatTimer.reset(generation: generation)
        await retryHelper.resetRetryState(generation: generation)
        // Don't cancel retryTask - it should persist to handle future retries
    }

    /// Sets up state after successful connection: resets retry state and starts heartbeat timer.
    /// This is called when connection is confirmed (ConnectionOpenEvent or CONNECTED event).
    private func setupSuccessfulConnection(generation: UInt64) async {
        guard generation == activeConnectionGeneration else { return }

        updateConnectionState(.connected)
        await retryHelper.resetRetryState(generation: generation)

        // Start heartbeat timer with initial timeout (default + buffer)
        await heartbeatTimer.startTimer(timeoutSeconds: HeartbeatTimer.initialTimeoutSeconds, generation: generation)
    }

    // MARK: - State Management

    private func updateConnectionState(_ newState: SseConnectionState) {
        guard newState != connectionState else { return }

        let oldState = connectionState.description
        logger.logWithModuleTag("SSE Manager: State transition: \(oldState) → \(newState.description)", level: .info)
        connectionState = newState

        switch newState {
        case .disconnected:
            logger.logWithModuleTag("SSE Manager: Connection is now closed", level: .info)
        case .connecting:
            logger.logWithModuleTag("SSE Manager: Connection initiated, waiting for response", level: .info)
        case .connected:
            logger.logWithModuleTag("SSE Manager: ✓ Connection established, listening for events", level: .info)
        case .disconnecting:
            logger.logWithModuleTag("SSE Manager: Connection stopping...", level: .info)
        }
    }

    // MARK: - Private Logging

    private func logRetryCancelled() {
        logger.logWithModuleTag("SSE Manager: Retry task cancelled", level: .debug)
    }
}

// swiftlint:enable file_length type_body_length
