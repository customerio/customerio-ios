import CioInternalCommon
import Foundation

// sourcery: InjectRegisterShared = "SseConnectionManager"
// sourcery: InjectSingleton
/// Manages SSE (Server-Sent Events) connections for real-time in-app message delivery.
/// Phase 2: Basic connection and event logging only.
/// Translates service events into connection state.
actor SseConnectionManager {
    private let logger: Logger
    private let inAppMessageManager: InAppMessageManager
    private let sseService: SseService
    private var connectionState: SseConnectionState = .disconnected
    private var streamTask: Task<Void, Never>?
    private let heartbeatTimer: HeartbeatTimer
    private var heartbeatCallbackInitialized = false

    init(
        logger: Logger,
        inAppMessageManager: InAppMessageManager,
        sseService: SseService
    ) {
        self.logger = logger
        self.inAppMessageManager = inAppMessageManager
        self.sseService = sseService
        self.heartbeatTimer = HeartbeatTimer(logger: logger)

        logger.logWithModuleTag("SseConnectionManager initialized", level: .debug)
    }

    /// Lazily initializes the heartbeat callback on first use.
    /// Called automatically before any connection attempt.
    private func ensureHeartbeatCallbackInitialized() async {
        guard !heartbeatCallbackInitialized else { return }

        await heartbeatTimer.setCallback { [weak self] in
            await self?.handleHeartbeatTimeout()
        }
        heartbeatCallbackInitialized = true
    }

    /// Starts an SSE connection to the queue consumer API.
    /// This method is idempotent - calling it multiple times while connected/connecting is safe.
    func startConnection(state: InAppMessageState) async {
        // Ensure heartbeat callback is initialized before any connection attempt
        await ensureHeartbeatCallbackInitialized()

        logger.logWithModuleTag("SSE Manager: startConnection called", level: .info)
        logger.logWithModuleTag("SSE Manager: useSse=\(state.useSse), userId=\(state.userId ?? "nil"), anonymousId=\(state.anonymousId ?? "nil")", level: .debug)

        if connectionState == .connecting || connectionState == .connected {
            logger.logWithModuleTag("SSE Manager: Connection is connected or connecting, ignoring", level: .debug)
            return
        }

        // Validate user identifier before updating state (matching Android's establishConnection pattern)
        // This prevents getting stuck in .connecting state if validation fails
        let userIdentifier = state.userId ?? state.anonymousId
        guard let userIdentifier = userIdentifier, !userIdentifier.isEmpty else {
            logger.logWithModuleTag("SSE Manager: Cannot establish connection: no user token available", level: .error)
            // This is a configuration issue, not a network issue - update state to disconnected like Android
            await handleConnectionFailed(SseError(message: "Cannot establish connection: no user token available"))
            return
        }

        streamTask?.cancel()

        // Build connection parameters (matching Android's establishConnection pattern)
        // Use shared session ID that persists for app lifetime (same as polling API uses)
        let sessionId = SessionManager.shared.sessionId
        let userToken = Data(userIdentifier.utf8).base64EncodedString()
        let connectionParams = SseConnectionParams(
            sseApiUrl: state.environment.networkSettings.sseAPI,
            sessionId: sessionId,
            userToken: userToken,
            siteId: state.siteId,
            dataCenter: state.dataCenter,
            isAnonymous: state.userId == nil
        )

        logger.logWithModuleTag("SSE Manager: Establishing connection for userToken=\(userIdentifier), sessionId=\(sessionId)", level: .debug)

        updateConnectionState(.connecting)
        // Use var so the closure captures by reference - by the time the Task body
        // executes, newTask will be assigned (Task body runs asynchronously)
        var newTask: Task<Void, Never>?

        newTask = Task { [weak self] in
            guard let self = self else { return }
            // Capture the task reference for later comparison
            guard let task = newTask else { return }

            let eventStream = await self.sseService.connect(params: connectionParams)
            for await event in eventStream {
                await self.handleEvent(event)
            }

            // Stream ended - pass task reference to verify it's still current
            // This guards against race condition where a new connection started
            // between stream ending and cleanup executing
            await self.handleStreamEnded(task: task)
        }

        streamTask = newTask
    }

    /// Stops the active SSE connection.
    /// This method is idempotent - calling it multiple times is safe.
    func stopConnection() async {
        logger.logWithModuleTag("SSE Manager: stopConnection called", level: .info)

        // Reset heartbeat timer when stopping connection
        await heartbeatTimer.reset()

        streamTask?.cancel()
        streamTask = nil

        await sseService.disconnect()

        updateConnectionState(.disconnected)

        logger.logWithModuleTag("SSE Manager: Connection stopped", level: .info)
    }

    // MARK: - Private Handlers

    /// Handles SSE events matching Android's sealed interface pattern
    private func handleEvent(_ event: SseEvent) async {
        switch event {
        case .connectionOpen:
            await handleConnectionOpen()

        case .serverEvent(let serverEvent):
            await handleServerEvent(serverEvent)

        case .connectionFailed(let error):
            await handleConnectionFailed(error)

        case .connectionClosed:
            await handleConnectionClosed()
        }
    }

    private func handleStreamEnded(task: Task<Void, Never>) async {
        // Only proceed if this is still the current stream task (guards against race condition
        // where a new connection was started before this cleanup executed)
        guard streamTask == task else {
            logger.logWithModuleTag("SSE Manager: Stale stream ended, ignoring (new connection already started)", level: .debug)
            return
        }

        logger.logWithModuleTag("SSE Manager: Event stream ended normally", level: .info)

        // Defensive cleanup - ensure timer is reset and state is correct
        // These may have already been handled by connection event handlers,
        // but we ensure consistency here to guard against edge cases
        await heartbeatTimer.reset()
        updateConnectionState(.disconnected)

        streamTask = nil
    }

    // MARK: - Connection Lifecycle Handlers

    private func handleConnectionOpen() async {
        logger.logWithModuleTag("SSE Manager: ✓ Connection opened", level: .info)
        updateConnectionState(.connected)

        // Start heartbeat timer with initial timeout (default + buffer)
        // This will be updated when we receive the first heartbeat event with server config
        await heartbeatTimer.startTimer(timeoutSeconds: HeartbeatTimer.initialTimeoutSeconds)
    }

    private func handleConnectionClosed() async {
        logger.logWithModuleTag("SSE Manager: Connection closed", level: .info)

        // Reset heartbeat timer when connection closes
        await heartbeatTimer.reset()

        updateConnectionState(.disconnected)
    }

    private func handleConnectionFailed(_ error: SseError) async {
        logger.logWithModuleTag("SSE Manager: ✗ Connection error: \(error.message)", level: .error)
        // Reset state to disconnected so future connection attempts can proceed
        // Retry logic will be handled in a future change
        updateConnectionState(.disconnected)

        // Reset heartbeat timer on connection failure
        await heartbeatTimer.reset()

        // we will handle errors and retry in the next change
    }

    // MARK: - Server Event Handlers

    private func handleServerEvent(_ event: ServerEvent) async {
        logger.logWithModuleTag("SSE Manager: ← Server event '\(event.eventType)'", level: .info)
        logger.logWithModuleTag("SSE Manager: Event data: \(event.data.prefix(100))", level: .debug)

        switch event.eventType {
        case .connected:
            logger.logWithModuleTag("SSE Manager: ✓ Server acknowledged connection", level: .info)
            updateConnectionState(.connected)

            // Restart heartbeat timer with initial timeout when server confirms connection
            await heartbeatTimer.startTimer(timeoutSeconds: HeartbeatTimer.initialTimeoutSeconds)

        case .heartbeat:
            await handleHeartbeatEvent(event)

        case .messages:
            handleMessagesEvent(event)

        case .ttlExceeded:
            logger.logWithModuleTag("SSE Manager: TTL exceeded, connection will be refreshed", level: .info)
            // Reset heartbeat timer before reconnection (matches Android's cleanupForReconnect)
            await heartbeatTimer.reset()
            // TODO: Trigger reconnection logic (will be implemented with error handling/retry)

        case .unknown:
            logger.logWithModuleTag("SSE Manager: Unknown server event type '\(event.rawEventType ?? "nil")', ignoring", level: .debug)
        }
    }

    private func handleHeartbeatEvent(_ event: ServerEvent) async {
        // Use server-provided interval or default if parsing failed (nil for edge cases like empty data, malformed JSON)
        let heartbeatInterval = event.heartbeatIntervalSeconds ?? HeartbeatTimer.defaultHeartbeatTimeoutSeconds
        let timeoutWithBuffer = heartbeatInterval + HeartbeatTimer.heartbeatBufferSeconds

        logger.logWithModuleTag("SSE Manager: ♥ Heartbeat received (interval: \(heartbeatInterval)s, timeout: \(timeoutWithBuffer)s)", level: .debug)

        // Restart heartbeat timer with the parsed interval + buffer
        await heartbeatTimer.startTimer(timeoutSeconds: timeoutWithBuffer)
    }

    /// Handles heartbeat timeout - called when no heartbeat is received within the expected timeframe
    private func handleHeartbeatTimeout() async {
        logger.logWithModuleTag("SSE Manager: ⚠️ Heartbeat timeout - connection appears stale", level: .error)

        // Reset heartbeat timer
        await heartbeatTimer.reset()

        // Cancel and clear the stale stream task
        streamTask?.cancel()
        streamTask = nil

        // Disconnect the underlying SSE service to release socket
        await sseService.disconnect()

        // Update connection state to disconnected
        updateConnectionState(.disconnected)

        // TODO: Trigger reconnection logic (will be implemented with error handling/retry)
    }

    private func handleMessagesEvent(_ event: ServerEvent) {
        logger.logWithModuleTag("SSE Manager: Message event received", level: .info)

        // Messages are already parsed by ServerEvent
        guard let messages = event.messages, !messages.isEmpty else {
            logger.logWithModuleTag("SSE Manager: No messages in event or failed to parse", level: .debug)
            return
        }

        logger.logWithModuleTag("SSE Manager: ✓ Received \(messages.count) message(s) from SSE", level: .info)

        // Dispatch to message queue processor (same as polling does)
        inAppMessageManager.dispatch(action: .processMessageQueue(messages: messages))
    }

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
        }
    }
}
