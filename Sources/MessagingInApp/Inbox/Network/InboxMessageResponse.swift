import Foundation

/// Internal model representing the API response for inbox messages.
///
/// This model handles optional fields from the API and maps to the domain model with defensive defaults.
struct InboxMessageResponse {
    let queueId: String
    let deliveryId: String?
    let expiry: String? // ISO 8601 date string
    let sentAt: Date // Parsed date
    let topics: [String]?
    let type: String?
    let opened: Bool?
    let priority: Int?
    let properties: [String: Any]?

    init(
        queueId: String,
        deliveryId: String?,
        expiry: String?,
        sentAt: Date,
        topics: [String]?,
        type: String?,
        opened: Bool?,
        priority: Int?,
        properties: [String: Any]?
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

    init?(dictionary: [String: Any]) {
        guard let queueId = dictionary["queueId"] as? String,
              let sentAtString = dictionary["sentAt"] as? String,
              let sentAtDate = Date.fromIso8601WithMilliseconds(sentAtString)
        else {
            return nil
        }
        self.init(
            queueId: queueId,
            deliveryId: dictionary["deliveryId"] as? String,
            expiry: dictionary["expiry"] as? String,
            sentAt: sentAtDate,
            topics: dictionary["topics"] as? [String],
            type: dictionary["type"] as? String,
            opened: dictionary["opened"] as? Bool,
            priority: dictionary["priority"] as? Int,
            properties: dictionary["properties"] as? [String: Any]
        )
    }
}
