import CioInternalCommon
import Foundation
import LDSwiftEventSource

// sourcery: InjectRegisterShared = "SseServiceProtocol"
// sourcery: InjectSingleton
/// SSE service layer that wraps LDSwiftEventSource library and provides AsyncStream interface.
///
/// Responsibilities:
/// - Build SSE URLs from connection parameters
/// - Wrap library callbacks as AsyncStream
/// - Track connection generations to prevent stale disconnects
/// - Provide clean async/await interface to SseConnectionManager
///
/// Uses a connection generation ID to ensure `disconnect()` only affects the specific
/// connection it was meant for, preventing race conditions where a new connection
/// could be killed by cleanup from an old `stopConnection()` call.
actor SseService: SseServiceProtocol {
    private let logger: Logger
    private var eventSource: LDSwiftEventSource.EventSource?
    /// The connection ID passed from the manager. Used to ensure disconnect() only affects the intended connection.
    private var activeConnectionId: UInt64 = 0

    init(logger: Logger) {
        self.logger = logger
        logger.logWithModuleTag("SseService initialized", level: .debug)
    }

    // MARK: - Public API

    /// Starts SSE connection using the provided state and connection ID.
    /// The connection ID is provided by the manager to ensure both layers share the same identifier.
    /// - Parameters:
    ///   - state: The current InAppMessageState containing user and environment info
    ///   - connectionId: The connection ID from the manager, used to coordinate disconnect operations
    /// - Returns: AsyncStream of SSE events
    func connect(state: InAppMessageState, connectionId: UInt64) -> AsyncStream<SseEvent> {
        // Store the connection ID from the manager - this ensures both layers share the same ID
        activeConnectionId = connectionId

        logger.logWithModuleTag("SseService: Initiating connection (connectionId \(connectionId))", level: .info)

        // Validate user identification
        let identifier = state.userId ?? state.anonymousId
        guard let identifier = identifier, !identifier.isEmpty else {
            logger.logWithModuleTag("SseService: Cannot connect without user identifier", level: .error)
            logger.logWithModuleTag("SseService: userId=\(state.userId ?? "nil"), anonymousId=\(state.anonymousId ?? "nil")", level: .debug)
            // Emit configuration error so manager can handle appropriately
            let stream = AsyncStream<SseEvent> { continuation in
                let error = SseError.configurationError(message: "Cannot connect without user identifier")
                logger.logWithModuleTag("SseService: Emitting configuration error - not retryable", level: .error)
                continuation.yield(.connectionFailed(error))
                continuation.finish()
            }
            return stream
        }

        // Build SSE URL
        guard let url = buildSseUrl(state: state, identifier: identifier) else {
            logger.logWithModuleTag("SseService: Failed to build connection URL", level: .error)
            let stream = AsyncStream<SseEvent> { continuation in
                let error = SseError.configurationError(message: "Failed to build SSE connection URL")
                logger.logWithModuleTag("SseService: Emitting configuration error - not retryable", level: .error)
                continuation.yield(.connectionFailed(error))
                continuation.finish()
            }
            return stream
        }

        logger.logWithModuleTag("SseService: Connecting to \(url.absoluteString)", level: .info)

        // Create stream and continuation separately to avoid race conditions
        // (Using backport for iOS 13+ compatibility; native makeStream() requires iOS 17+)
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)

        // Create event handler with continuation
        let handler = StreamEventHandler(continuation: continuation, logger: logger)

        // Configure EventSource
        let headers = buildHeaders(state: state)
        var config = LDSwiftEventSource.EventSource.Config(handler: handler, url: url)
        config.headers = headers
        config.idleTimeout = 300.0 // 5 minutes read timeout

        // Handle connection errors - emit to our stream before shutting down
        // This is called INSTEAD of onError for connection-level failures
        config.connectionErrorHandler = { [logger] error in
            logger.logWithModuleTag("SseService: ✗ Connection error: \(error.localizedDescription)", level: .error)

            // Extract HTTP response code if available (LDSwiftEventSource provides UnsuccessfulResponseError for HTTP errors)
            let responseCode = (error as? UnsuccessfulResponseError)?.responseCode
            if let code = responseCode {
                logger.logWithModuleTag("SseService: HTTP response code: \(code)", level: .debug)
            }

            // Classify and emit error to stream
            let sseError = classifySseError(error, responseCode: responseCode)
            logger.logWithModuleTag("SseService: Classified as \(sseError.errorType), shouldRetry: \(sseError.shouldRetry)", level: .info)
            continuation.yield(.connectionFailed(sseError))

            // Shutdown - we'll handle retry logic ourselves
            return .shutdown
        }

        // Create EventSource and store reference synchronously (no race condition)
        let newEventSource = LDSwiftEventSource.EventSource(config: config)
        eventSource = newEventSource

        // Start connection
        newEventSource.start()
        logger.logWithModuleTag("SseService: EventSource started", level: .debug)

        // Handle stream termination (called when consumer stops iterating or Task is cancelled)
        continuation.onTermination = { [weak newEventSource] _ in
            newEventSource?.stop()
        }

        return stream
    }

    /// Stops the SSE connection only if the connection ID matches.
    ///
    /// This prevents race conditions where `stopConnection()` cleanup could kill
    /// a newer connection that started while the old stop was awaiting.
    ///
    /// - Parameter connectionId: The connection ID to disconnect
    func disconnect(connectionId: UInt64) {
        guard activeConnectionId == connectionId else {
            logger.logWithModuleTag("SseService: Skipping disconnect - connectionId mismatch (requested \(connectionId) vs current \(activeConnectionId))", level: .debug)
            return
        }

        logger.logWithModuleTag("SseService: Disconnecting (connectionId \(connectionId))", level: .info)

        eventSource?.stop()
        eventSource = nil

        logger.logWithModuleTag("SseService: Disconnected", level: .debug)
    }

    // MARK: - Private Helpers

    private func buildSseUrl(state: InAppMessageState, identifier: String) -> URL? {
        // SSE API URL includes full path (like Android's getSseApiUrl())
        let sseUrlString = state.environment.networkSettings.sseAPI
        guard var components = URLComponents(string: sseUrlString) else {
            logger.logWithModuleTag("SseService: Invalid SSE URL: \(sseUrlString)", level: .error)
            return nil
        }

        // Add query parameters (matching Android's createSseRequest)
        let userToken = Data(identifier.utf8).base64EncodedString()
        let sessionId = SessionManager.shared.sessionId
        components.queryItems = [
            URLQueryItem(name: "sessionId", value: sessionId),
            URLQueryItem(name: "siteId", value: state.siteId),
            URLQueryItem(name: "userToken", value: userToken)
        ]

        logger.logWithModuleTag("SseService: Built URL with siteId=\(state.siteId), sessionId=\(sessionId), identifier=\(identifier)", level: .debug)

        return components.url
    }

    /// Builds common headers for SSE connection (matching Android's addCommonHeaders with includeUserToken=false)
    /// SSE uses userToken in URL query parameter, not in header
    private func buildHeaders(state: InAppMessageState) -> [String: String] {
        let sdkClient = DIGraphShared.shared.sdkClient
        let isAnonymous = state.userId == nil

        return [
            HTTPHeader.siteId.rawValue: state.siteId,
            HTTPHeader.cioDataCenter.rawValue: state.dataCenter,
            HTTPHeader.cioClientPlatform.rawValue: sdkClient.source.lowercased() + "-apple",
            HTTPHeader.cioClientVersion.rawValue: sdkClient.sdkVersion,
            HTTPHeader.userAnonymous.rawValue: String(isAnonymous)
            // Note: userToken is NOT included in headers for SSE - it's in the URL query params
        ]
    }
}

// MARK: - LDSwiftEventSource Event Handler

/// Bridges LDSwiftEventSource callbacks to our AsyncStream.
/// Maps library callbacks to SseEvent types matching Android's sealed interface.
private final class StreamEventHandler: EventHandler {
    private let continuation: AsyncStream<SseEvent>.Continuation
    private let logger: Logger

    init(continuation: AsyncStream<SseEvent>.Continuation, logger: Logger) {
        self.continuation = continuation
        self.logger = logger
    }

    func onOpened() {
        logger.logWithModuleTag("SseService: ✓ Connection opened", level: .info)
        // Emit ConnectionOpenEvent (matches Android's ConnectionOpenEvent)
        continuation.yield(.connectionOpen)
    }

    func onClosed() {
        logger.logWithModuleTag("SseService: Connection closed", level: .info)
        // Emit ConnectionClosedEvent before finishing (matches Android's ConnectionClosedEvent)
        continuation.yield(.connectionClosed)
        continuation.finish()
    }

    func onMessage(eventType: String, messageEvent: MessageEvent) {
        logger.logWithModuleTag("SseService: → Server event - type: '\(eventType)'", level: .info)
        logger.logWithModuleTag("SseService:   data: \(messageEvent.data.prefix(100))\(messageEvent.data.count > 100 ? "..." : "")", level: .debug)

        // Emit ServerEvent (matches Android's ServerEvent)
        let serverEvent = ServerEvent(
            id: messageEvent.lastEventId,
            type: eventType.isEmpty ? nil : eventType,
            data: messageEvent.data
        )
        continuation.yield(.serverEvent(serverEvent))
    }

    func onComment(comment: String) {
        logger.logWithModuleTag("SseService: Comment received: \(comment.prefix(50))", level: .debug)
    }

    func onError(error: Error) {
        logger.logWithModuleTag("SseService: ✗ Error: \(error.localizedDescription)", level: .error)

        // Classify error for retry logic (matches Android's classifySseError)
        // Extract HTTP response code if available
        var responseCode: Int?

        // Check for UnsuccessfulResponseError (HTTP error responses from LDSwiftEventSource)
        if let unsuccessfulResponse = error as? UnsuccessfulResponseError {
            responseCode = unsuccessfulResponse.responseCode
            logger.logWithModuleTag("SseService: HTTP response code: \(responseCode!)", level: .debug)
        } else if let urlError = error as? URLError {
            // URLError for network-level issues (no HTTP status code available)
            logger.logWithModuleTag("SseService: URLError code: \(urlError.code.rawValue) (\(urlError.code))", level: .debug)
        }

        let sseError = classifySseError(error, responseCode: responseCode)
        logger.logWithModuleTag("SseService: Classified as \(sseError.errorType), shouldRetry: \(sseError.shouldRetry)", level: .info)
        continuation.yield(.connectionFailed(sseError))
        continuation.finish()
    }
}
