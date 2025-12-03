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
        case ttlExceeded = "ttl_exceeded"
        case unknown

        var description: String { rawValue }

        init(rawValue: String) {
            switch rawValue {
            case "connected": self = .connected
            case "heartbeat": self = .heartbeat
            case "messages", "": self = .messages // Empty/nil defaults to messages per SSE spec
            case "ttl_exceeded": self = .ttlExceeded
            default: self = .unknown
            }
        }
    }

    let eventType: EventType
    let data: String
    let id: String? // Event ID for Last-Event-ID tracking

    /// Parsed messages (only populated for message events)
    let messages: [Message]?

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
    }

    /// Parses message data from SSE event into Message objects (same as polling does)
    /// This method is resilient - it returns nil for any parsing failure without throwing
    /// Note: No logging here since this is called from background thread; caller handles logging
    private static func parseMessages(eventType: EventType, data: String) -> [Message]? {
        // Only parse messages for message events
        guard eventType == .messages else { return nil }

        // Empty data is valid (no messages)
        guard !data.isEmpty else { return nil }

        // Convert to UTF8 data
        guard let jsonData = data.data(using: .utf8) else { return nil }

        do {
            // Parse JSON - expect array of dictionaries (same format as polling API)
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: .allowFragments)

            guard let messageArray = jsonObject as? [[String: Any?]] else { return nil }

            // Convert dictionaries to UserQueueResponse, then to Message
            // compactMap ensures invalid items are skipped without failing the whole batch
            let userQueueResponses = messageArray.compactMap { UserQueueResponse(dictionary: $0) }
            let messages = userQueueResponses.map { $0.toMessage() }

            return messages.isEmpty ? nil : messages
        } catch {
            return nil
        }
    }
}

// MARK: - SSE Error

/// Represents errors that occur during SSE connection or communication.
/// Corresponds to Android's `SseError`.
struct SseError: Equatable, Error {
    let message: String
    let underlyingError: Error?

    init(message: String, underlyingError: Error? = nil) {
        self.message = message
        self.underlyingError = underlyingError
    }

    static func == (lhs: SseError, rhs: SseError) -> Bool {
        lhs.message == rhs.message
    }
}
