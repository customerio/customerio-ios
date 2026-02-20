import CioInternalCommon
import Foundation

/// Factory for creating InboxMessage from various sources.
public enum InboxMessageFactory {
    /// Converts API response to domain model with defensive defaults.
    static func fromResponse(_ response: InboxMessageResponse) -> InboxMessage {
        // Parse ISO 8601 dates using shared extension
        let expiryDate: Date? = response.expiry.flatMap { Date.fromIso8601WithMilliseconds($0) }

        return InboxMessage(
            queueId: response.queueId,
            deliveryId: response.deliveryId,
            expiry: expiryDate,
            sentAt: response.sentAt,
            topics: response.topics ?? [],
            type: response.type ?? "",
            opened: response.opened ?? false,
            priority: response.priority,
            properties: response.properties ?? [:]
        )
    }

    /// Converts dictionary to InboxMessage for SDK wrapper integrations (React Native, Flutter).
    ///
    /// - Parameter dictionary: Dictionary with queueId (String) and sentAt (NSNumber, Unix milliseconds) required
    /// - Returns: InboxMessage if required fields are valid, nil otherwise
    public static func fromDictionary(_ dictionary: [String: Any]) -> InboxMessage? {
        // Required fields
        guard let queueId = dictionary["queueId"] as? String else {
            return nil
        }

        // sentAt is required - convert from Unix timestamp (milliseconds)
        guard let sentAtMillis = dictionary["sentAt"] as? NSNumber else {
            return nil
        }
        let sentAt = Date(timeIntervalSince1970: sentAtMillis.doubleValue / 1000.0)

        // Optional fields with defaults
        let deliveryId = dictionary["deliveryId"] as? String
        let expiry: Date? = {
            if let expiryMillis = dictionary["expiry"] as? NSNumber {
                return Date(timeIntervalSince1970: expiryMillis.doubleValue / 1000.0)
            }
            return nil
        }()
        let topics = (dictionary["topics"] as? [String]) ?? []
        let type = dictionary["type"] as? String ?? ""
        let opened = dictionary["opened"] as? Bool ?? false
        let priority: Int? = {
            if let priorityNumber = dictionary["priority"] as? NSNumber {
                return priorityNumber.intValue
            }
            return nil
        }()
        let properties = dictionary["properties"] as? [String: Any] ?? [:]

        return InboxMessage(
            queueId: queueId,
            deliveryId: deliveryId,
            expiry: expiry,
            sentAt: sentAt,
            topics: topics,
            type: type,
            opened: opened,
            priority: priority,
            properties: properties
        )
    }
}
