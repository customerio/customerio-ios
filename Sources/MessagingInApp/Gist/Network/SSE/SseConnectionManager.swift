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

    init(
        logger: Logger,
        inAppMessageManager: InAppMessageManager,
        sseService: SseService
    ) {
        self.logger = logger
        self.inAppMessageManager = inAppMessageManager
        self.sseService = sseService
        logger.logWithModuleTag("SseConnectionManager initialized", level: .debug)
    }

    /// Starts an SSE connection to the queue consumer API.
    /// This method is idempotent - calling it multiple times while connected/connecting is safe.
    func startConnection(state: InAppMessageState) async {
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
            handleConnectionFailed(SseError(message: "Cannot establish connection: no user token available"))
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
        streamTask = Task { [weak self] in
            guard let self = self else { return }

            let eventStream = await self.sseService.connect(params: connectionParams)
            for await event in eventStream {
                await self.handleEvent(event)
            }

            // Stream ended - only cleanup if not cancelled
            // If cancelled, the canceller (stopConnection or new startConnection) handles cleanup
            guard !Task.isCancelled else { return }
            await self.clearStreamTask()
            logger.logWithModuleTag("SSE Manager: Event stream ended normally", level: .info)
        }
    }

    /// Stops the active SSE connection.
    /// This method is idempotent - calling it multiple times is safe.
    func stopConnection() async {
        logger.logWithModuleTag("SSE Manager: stopConnection called", level: .info)

        streamTask?.cancel()
        streamTask = nil

        await sseService.disconnect()

        updateConnectionState(.disconnected)

        logger.logWithModuleTag("SSE Manager: Connection stopped", level: .info)
    }

    // MARK: - Private Handlers

    /// Handles SSE events matching Android's sealed interface pattern
    private func handleEvent(_ event: SseEvent) {
        switch event {
        case .connectionOpen:
            handleConnectionOpen()

        case .serverEvent(let serverEvent):
            handleServerEvent(serverEvent)

        case .connectionFailed(let error):
            handleConnectionFailed(error)

        case .connectionClosed:
            handleConnectionClosed()
        }
    }

    private func clearStreamTask() {
        streamTask = nil
    }

    // MARK: - Connection Lifecycle Handlers

    private func handleConnectionOpen() {
        logger.logWithModuleTag("SSE Manager: ✓ Connection opened", level: .info)
        updateConnectionState(.connected)
    }

    private func handleConnectionClosed() {
        logger.logWithModuleTag("SSE Manager: Connection closed", level: .info)
        updateConnectionState(.disconnected)
    }

    private func handleConnectionFailed(_ error: SseError) {
        logger.logWithModuleTag("SSE Manager: ✗ Connection error: \(error.message)", level: .error)
        // Reset state to disconnected so future connection attempts can proceed
        // Retry logic will be handled in a future change
        updateConnectionState(.disconnected)
    }

    // MARK: - Server Event Handlers

    private func handleServerEvent(_ event: ServerEvent) {
        logger.logWithModuleTag("SSE Manager: ← Server event '\(event.eventType)'", level: .info)
        logger.logWithModuleTag("SSE Manager: Event data: \(event.data.prefix(100))", level: .debug)

        switch event.eventType {
        case .connected:
            logger.logWithModuleTag("SSE Manager: ✓ Server acknowledged connection", level: .info)
            updateConnectionState(.connected)

        case .heartbeat:
            logger.logWithModuleTag("SSE Manager: ♥ Heartbeat received", level: .debug)

        case .messages:
            handleMessagesEvent(event)

        case .ttlExceeded:
            logger.logWithModuleTag("SSE Manager: TTL exceeded, connection will be refreshed", level: .info)

        case .unknown:
            logger.logWithModuleTag("SSE Manager: Unknown server event type '\(event.rawEventType ?? "nil")', ignoring", level: .debug)
        }
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
