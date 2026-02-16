import Foundation

/// Represents an inbox message for a user.
///
/// Inbox messages are persistent messages that can be displayed in a message center or inbox UI.
/// They support read/unread states, expiration, and custom properties.
///
/// Conforms to `@unchecked Sendable` as it's an immutable struct with values safely copied across concurrency boundaries.
public struct InboxMessage: Equatable, CustomStringConvertible, @unchecked Sendable {
    /// Internal queue identifier (for SDK use)
    public let queueId: String

    /// Unique identifier for this message delivery
    public let deliveryId: String?

    /// Optional expiration date. Messages may be hidden after this date.
    public let expiry: Date?

    /// Date when the message was sent
    public let sentAt: Date

    /// List of topic identifiers associated with this message. Empty list if no topics.
    public let topics: [String]

    /// Message type identifier
    public let type: String

    /// Whether the user has opened/read this message
    public let opened: Bool

    /// Priority for message ordering. Lower values = higher priority (e.g., 1 is higher priority than 100)
    public let priority: Int?

    /// Custom key-value properties associated with this message
    public let properties: [String: Any]

    public init(
        queueId: String,
        deliveryId: String?,
        expiry: Date?,
        sentAt: Date,
        topics: [String],
        type: String,
        opened: Bool,
        priority: Int?,
        properties: [String: Any]
    ) {
        self.queueId = queueId
        self.deliveryId = deliveryId
        self.expiry = expiry
        self.sentAt = sentAt
        self.topics = topics
        self.type = type
        self.opened = opened
        self.priority = priority
        self.properties = properties
    }

    /// Creates a copy of the message with optional field overrides.
    /// Note: Cannot explicitly set optional fields to nil due to Swift limitation.
    func copy(
        queueId: String? = nil,
        deliveryId: String?? = nil,
        expiry: Date?? = nil,
        sentAt: Date? = nil,
        topics: [String]? = nil,
        type: String? = nil,
        opened: Bool? = nil,
        priority: Int?? = nil,
        properties: [String: Any]? = nil
    ) -> InboxMessage {
        InboxMessage(
            queueId: queueId ?? self.queueId,
            deliveryId: deliveryId ?? self.deliveryId,
            expiry: expiry ?? self.expiry,
            sentAt: sentAt ?? self.sentAt,
            topics: topics ?? self.topics,
            type: type ?? self.type,
            opened: opened ?? self.opened,
            priority: priority ?? self.priority,
            properties: properties ?? self.properties
        )
    }

    // MARK: - Equatable

    /// Equality compares all properties (queueId, opened, priority, etc.).
    /// Used for Array comparison to detect when any message property changes.
    public static func == (lhs: InboxMessage, rhs: InboxMessage) -> Bool {
        lhs.queueId == rhs.queueId &&
            lhs.deliveryId == rhs.deliveryId &&
            lhs.expiry == rhs.expiry &&
            lhs.sentAt == rhs.sentAt &&
            lhs.topics == rhs.topics &&
            lhs.type == rhs.type &&
            lhs.opened == rhs.opened &&
            lhs.priority == rhs.priority &&
            lhs.properties.count == rhs.properties.count // Compare count only since [String: Any] isn't Equatable
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        let deliveryIdStr = deliveryId.map { "'\($0)'" } ?? "nil"
        let expiryStr = expiry.map { "\($0)" } ?? "nil"
        let priorityStr = priority.map { "\($0)" } ?? "nil"
        return """
        InboxMessage(queueId: '\(queueId)', deliveryId: \(deliveryIdStr), expiry: \(expiryStr), \
        sentAt: \(sentAt), topics: \(topics), type: '\(type)', opened: \(opened), priority: \(priorityStr), \
        properties: \(properties))
        """
    }

    // MARK: - Logging

    /// Concise string representation for logging purposes.
    /// Used for getting details about the InboxMessage object for sending to logs.
    var describeForLogs: String {
        let deliveryIdStr = deliveryId ?? "nil"
        return "\(queueId) (deliveryId: \(deliveryIdStr))"
    }
}
