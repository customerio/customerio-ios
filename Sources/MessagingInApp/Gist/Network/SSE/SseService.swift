import CioInternalCommon
import Foundation
import LDSwiftEventSource

/// Parameters required to establish an SSE connection.
/// Matches Android's connectSse() parameters with additional header info.
struct SseConnectionParams {
    let sseApiUrl: String
    let sessionId: String
    let userToken: String // Base64 encoded user identifier
    let siteId: String
    let dataCenter: String
    let isAnonymous: Bool
}

// sourcery: InjectRegisterShared = "SseService"
// sourcery: InjectSingleton
/// SSE service layer that wraps LDSwiftEventSource library and provides AsyncStream interface
/// Responsibilities:
/// - Build SSE URLs from connection parameters
/// - Wrap library callbacks as AsyncStream
/// - Provide clean async/await interface to SseConnectionManager
actor SseService {
    private let logger: Logger
    private var eventSource: LDSwiftEventSource.EventSource?

    init(logger: Logger) {
        self.logger = logger
        logger.logWithModuleTag("SseService initialized", level: .debug)
    }

    // MARK: - Public API

    /// Starts SSE connection using validated connection parameters.
    /// Returns AsyncStream of events for the caller to iterate over.
    /// - Parameter params: Pre-validated connection parameters from SseConnectionManager
    /// - Returns: AsyncStream of SSE events
    /// - Note: Caller (SseConnectionManager) validates and builds params before calling this method
    func connect(params: SseConnectionParams) -> AsyncStream<SseEvent> {
        logger.logWithModuleTag("SseService: Initiating connection", level: .info)

        // Build SSE URL from params
        guard let url = buildSseUrl(params: params) else {
            logger.logWithModuleTag("SseService: Failed to build connection URL", level: .error)
            // Emit connectionFailed event so manager can reset state properly
            return AsyncStream { continuation in
                let error = SseError(message: "Failed to build SSE connection URL")
                continuation.yield(.connectionFailed(error))
                continuation.finish()
            }
        }

        logger.logWithModuleTag("SseService: Connecting to \(url.absoluteString)", level: .info)

        // Create stream and continuation separately to avoid race conditions
        // (Using backport for iOS 13+ compatibility; native makeStream() requires iOS 17+)
        let (stream, continuation) = AsyncStreamBackport.makeStream(of: SseEvent.self)

        // Create event handler with continuation
        let handler = StreamEventHandler(continuation: continuation, logger: logger)

        // Configure EventSource
        let headers = buildHeaders(params: params)
        var config = LDSwiftEventSource.EventSource.Config(handler: handler, url: url)
        config.headers = headers
        config.idleTimeout = 300.0 // 5 minutes read timeout

        // Disable automatic retry - we'll handle reconnection logic ourselves
        config.connectionErrorHandler = { _ in .shutdown }

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

    /// Stops the SSE connection
    func disconnect() {
        logger.logWithModuleTag("SseService: Disconnecting", level: .info)

        eventSource?.stop()
        eventSource = nil

        logger.logWithModuleTag("SseService: Disconnected", level: .debug)
    }

    // MARK: - Private Helpers

    private func buildSseUrl(params: SseConnectionParams) -> URL? {
        guard var components = URLComponents(string: params.sseApiUrl) else {
            logger.logWithModuleTag("SseService: Invalid SSE URL: \(params.sseApiUrl)", level: .error)
            return nil
        }

        // Add query parameters (matching Android's createSseRequest)
        components.queryItems = [
            URLQueryItem(name: "sessionId", value: params.sessionId),
            URLQueryItem(name: "siteId", value: params.siteId),
            URLQueryItem(name: "userToken", value: params.userToken)
        ]

        logger.logWithModuleTag("SseService: Built URL with siteId=\(params.siteId), sessionId=\(params.sessionId)", level: .debug)

        return components.url
    }

    /// Builds common headers for SSE connection (matching Android's addCommonHeaders with includeUserToken=false)
    /// SSE uses userToken in URL query parameter, not in header
    private func buildHeaders(params: SseConnectionParams) -> [String: String] {
        let sdkClient = DIGraphShared.shared.sdkClient

        return [
            HTTPHeader.siteId.rawValue: params.siteId,
            HTTPHeader.cioDataCenter.rawValue: params.dataCenter,
            HTTPHeader.cioClientPlatform.rawValue: sdkClient.source.lowercased() + "-apple",
            HTTPHeader.cioClientVersion.rawValue: sdkClient.sdkVersion,
            HTTPHeader.userAnonymous.rawValue: String(params.isAnonymous)
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

        let sseError = SseError(message: error.localizedDescription, underlyingError: error)
        continuation.yield(.connectionFailed(sseError))
        continuation.finish()
    }
}
