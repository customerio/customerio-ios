import Foundation

// MARK: - SSE Event (matches Android's sealed interface)

/// Represents an SSE event from the server connection.
/// Aligns with Android's `SseEvent` sealed interface.
enum SseEvent: Equatable {
    /// Connection opened event (emitted by library's onOpen callback).
    /// Corresponds to Android's `ConnectionOpenEvent`.
    case connectionOpen

    /// Server event with type and data.
    /// Corresponds to Android's `ServerEvent`.
    case serverEvent(ServerEvent)

    /// Connection failed event with error details.
    /// Corresponds to Android's `ConnectionFailedEvent`.
    case connectionFailed(SseError)

    /// Connection closed event (emitted by library's onClosed callback).
    /// Corresponds to Android's `ConnectionClosedEvent`.
    case connectionClosed
}

// MARK: - Server Event

/// Represents a server event with type and data.
/// Corresponds to Android's `ServerEvent` data class.
struct ServerEvent: Equatable {
    /// Server event types (matches Android's ServerEvent companion object constants)
    enum EventType: String, Equatable, CustomStringConvertible {
        case connected
        case heartbeat
        case messages
        case inboxMessages = "inbox_messages"
        case ttlExceeded = "ttl_exceeded"
        case unknown

        var description: String { rawValue }

        init(rawValue: String) {
            switch rawValue {
            case "connected": self = .connected
            case "heartbeat": self = .heartbeat
            case "messages", "": self = .messages // Empty/nil defaults to messages per SSE spec
            case "inbox_messages": self = .inboxMessages
            case "ttl_exceeded": self = .ttlExceeded
            default: self = .unknown
            }
        }
    }

    let eventType: EventType
    let data: String
    let id: String? // Event ID for Last-Event-ID tracking

    /// Parsed in-app messages (only populated for message events)
    let messages: [Message]?

    /// Parsed inbox messages (only populated for inbox_messages events)
    let inboxMessages: [InboxMessage]?

    /// Parsed heartbeat interval in seconds.
    /// Corresponds to Android's `parseHeartbeatTimeout` function.
    /// - For heartbeat events: Always contains a valid value (parsed or default 30s)
    /// - For non-heartbeat events: nil
    let heartbeatIntervalSeconds: TimeInterval?

    /// Raw event type string (preserved for logging unknown types)
    let rawEventType: String?

    /// Creates a ServerEvent from raw SSE fields
    /// Parsing is resilient - malformed data results in nil messages, not errors
    init(id: String?, type: String?, data: String) {
        self.id = id
        self.rawEventType = type
        self.eventType = EventType(rawValue: type ?? "")
        self.data = data
        self.messages = Self.parseMessages(eventType: eventType, data: data)
        self.inboxMessages = Self.parseInboxMessages(eventType: eventType, data: data)
        self.heartbeatIntervalSeconds = Self.parseHeartbeatInterval(eventType: eventType, data: data)
    }

    /// Generic helper to parse message arrays from SSE event data
    /// This method is resilient - it returns nil for any parsing failure without throwing
    /// Note: No logging here since this is called from background thread; caller handles logging
    private static func parseMessageArray<Response, Domain>(
        eventType: EventType,
        expectedType: EventType,
        data: String,
        parser: ([String: Any?]) -> Response?,
        mapper: (Response) -> Domain
    ) -> [Domain]? {
        // Only parse for the expected event type
        guard eventType == expectedType else { return nil }

        // Empty data is valid (no messages)
        guard !data.isEmpty else { return nil }

        // Convert to UTF8 data
        guard let jsonData = data.data(using: .utf8) else { return nil }

        do {
            // Parse JSON - expect array of dictionaries (same format as polling API)
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: .allowFragments)

            guard let messageArray = jsonObject as? [[String: Any]] else { return nil }

            // Convert dictionaries to InAppMessageResponse, then to Message
            // compactMap ensures invalid items are skipped without failing the whole batch
            let inAppMessageResponses = messageArray.compactMap { InAppMessageResponse(dictionary: $0) }
            let messages = inAppMessageResponses.map { $0.toMessage() }

            return result.isEmpty ? nil : result
        } catch {
            return nil
        }
    }

    /// Parses in-app messages from "messages" event
    private static func parseMessages(eventType: EventType, data: String) -> [Message]? {
        parseMessageArray(
            eventType: eventType,
            expectedType: .messages,
            data: data,
            parser: { InAppMessageResponse(dictionary: $0) },
            mapper: { $0.toMessage() }
        )
    }

    /// Parses inbox messages from "inbox_messages" event
    private static func parseInboxMessages(eventType: EventType, data: String) -> [InboxMessage]? {
        parseMessageArray(
            eventType: eventType,
            expectedType: .inboxMessages,
            data: data,
            parser: { InboxMessageResponse(dictionary: $0) },
            mapper: { $0.toDomainModel() }
        )
    }

    /// Parses heartbeat interval from heartbeat event data.
    /// Corresponds to Android's `parseHeartbeatTimeout` function.
    ///
    /// Expected format: `{"heartbeat": 30}` where 30 is the interval in seconds.
    ///
    /// - Parameters:
    ///   - eventType: The event type (only parses for heartbeat events)
    ///   - data: JSON data from heartbeat event
    /// - Returns: For heartbeat events: parsed interval or default (30s) if parsing fails/invalid.
    ///            For non-heartbeat events: nil
    private static func parseHeartbeatInterval(eventType: EventType, data: String) -> TimeInterval? {
        // Only parse for heartbeat events
        guard eventType == .heartbeat else { return nil }

        let defaultTimeout = HeartbeatTimer.defaultHeartbeatTimeoutSeconds

        // Empty data means use default
        guard !data.isEmpty, !data.trimmingCharacters(in: .whitespaces).isEmpty else {
            return defaultTimeout
        }

        // Convert to UTF8 data
        guard let jsonData = data.data(using: .utf8) else {
            return defaultTimeout
        }

        do {
            // Parse JSON - expect object with "heartbeat" key
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: .allowFragments)

            guard let dictionary = jsonObject as? [String: Any],
                  let heartbeatValue = dictionary["heartbeat"]
            else {
                return defaultTimeout
            }

            // Handle both Int and Double values, validating for positive values
            // Non-positive values would cause immediate timer expiration, so use default
            if let intValue = heartbeatValue as? Int, intValue > 0 {
                return TimeInterval(intValue)
            } else if let doubleValue = heartbeatValue as? Double, doubleValue > 0 {
                return doubleValue
            }

            return defaultTimeout
        } catch {
            return defaultTimeout
        }
    }
}

// MARK: - SSE Error

/// Represents different types of SSE errors with their classification for retry logic.
/// Corresponds to Android's `SseError` sealed class.
enum SseError: Equatable, Error {
    /// Network-level error (connection failed, no internet, etc.) - retryable
    case networkError(message: String, underlyingError: Error?)

    /// Heartbeat timeout - connection appears stale - retryable
    case timeoutError

    /// Server returned an error response
    /// - Parameters:
    ///   - message: Error description
    ///   - responseCode: HTTP status code (if available)
    ///   - shouldRetry: Whether this error should trigger retry logic
    case serverError(message: String, responseCode: Int?, shouldRetry: Bool)

    /// Unknown/unexpected error - retryable by default
    case unknownError(message: String, underlyingError: Error?)

    /// Configuration error (e.g., missing user token) - not retryable
    case configurationError(message: String)

    /// Whether this error should trigger retry logic
    /// Corresponds to Android's `shouldRetry` property
    var shouldRetry: Bool {
        switch self {
        case .networkError:
            return true
        case .timeoutError:
            return true
        case .serverError(_, _, let shouldRetry):
            return shouldRetry
        case .unknownError:
            return true
        case .configurationError:
            return false
        }
    }

    /// Human-readable error message for logging
    var message: String {
        switch self {
        case .networkError(let message, _):
            return "Network error: \(message)"
        case .timeoutError:
            return "Connection timeout"
        case .serverError(let message, let code, _):
            if let code = code {
                return "Server error (HTTP \(code)): \(message)"
            }
            return "Server error: \(message)"
        case .unknownError(let message, _):
            return "Unknown error: \(message)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        }
    }

    /// Error type name for logging (matches Android error class names)
    var errorType: String {
        switch self {
        case .networkError:
            return "NetworkError"
        case .timeoutError:
            return "TimeoutError"
        case .serverError(_, let code, _):
            if let code = code {
                return "ServerError(\(code))"
            }
            return "ServerError"
        case .unknownError:
            return "UnknownError"
        case .configurationError:
            return "ConfigurationError"
        }
    }

    static func == (lhs: SseError, rhs: SseError) -> Bool {
        switch (lhs, rhs) {
        case (.networkError(let lhsMsg, _), .networkError(let rhsMsg, _)):
            return lhsMsg == rhsMsg
        case (.timeoutError, .timeoutError):
            return true
        case (.serverError(let lhsMsg, let lhsCode, let lhsRetry), .serverError(let rhsMsg, let rhsCode, let rhsRetry)):
            return lhsMsg == rhsMsg && lhsCode == rhsCode && lhsRetry == rhsRetry
        case (.unknownError(let lhsMsg, _), .unknownError(let rhsMsg, _)):
            return lhsMsg == rhsMsg
        case (.configurationError(let lhsMsg), .configurationError(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
}

// MARK: - Error Classification

/// Classifies errors into SSE error types for appropriate retry handling.
/// Corresponds to Android's `classifySseError` function.
func classifySseError(_ error: Error, responseCode: Int? = nil) -> SseError {
    // Check for URL errors (network issues)
    if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed:
            return .networkError(message: urlError.localizedDescription, underlyingError: urlError)
        case .timedOut:
            return .timeoutError
        default:
            return .networkError(message: urlError.localizedDescription, underlyingError: urlError)
        }
    }

    // Check for HTTP response codes
    if let code = responseCode {
        let shouldRetry: Bool
        switch code {
        case 408, 429: // Request Timeout, Too Many Requests
            shouldRetry = true
        case 500 ... 599: // Server errors
            shouldRetry = true
        case 400 ... 499: // Client errors (except 408, 429)
            shouldRetry = false
        default:
            shouldRetry = true
        }
        return .serverError(message: error.localizedDescription, responseCode: code, shouldRetry: shouldRetry)
    }

    // Default to unknown error (retryable)
    return .unknownError(message: error.localizedDescription, underlyingError: error)
}
