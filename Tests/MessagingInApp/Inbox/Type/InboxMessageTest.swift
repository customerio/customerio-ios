@testable import CioInternalCommon
@testable import CioMessagingInApp
import Foundation
import Testing

@Suite("InboxMessage Tests")
struct InboxMessageTest {
    @Test("Equality compares all properties")
    func equalityComparesAllProperties() {
        let sentAt = Date()
        let message1 = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: sentAt,
            topics: [],
            type: "",
            opened: false,
            priority: 5,
            properties: [:]
        )

        let message2 = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-2", // Different
            expiry: nil,
            sentAt: sentAt,
            topics: ["different"], // Different
            type: "different", // Different
            opened: true, // Different
            priority: 10, // Different
            properties: ["key": "value"] // Different
        )

        // Not equal because properties differ (all-properties equality)
        #expect(message1 != message2)
    }

    @Test("Equality when all properties match")
    func equalityWhenAllPropertiesMatch() {
        let sentAt = Date()
        let message1 = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: sentAt,
            topics: ["promo"],
            type: "in-app",
            opened: true,
            priority: 5,
            properties: ["key": "value"]
        )

        let message2 = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: sentAt,
            topics: ["promo"],
            type: "in-app",
            opened: true,
            priority: 5,
            properties: ["key": "value"]
        )

        // Equal because all properties match
        #expect(message1 == message2)
    }

    @Test("Equality detects queueId changes")
    func equalityDetectsQueueIdChanges() {
        let sentAt = Date()
        let message1 = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: sentAt,
            topics: [],
            type: "",
            opened: false,
            priority: 5,
            properties: [:]
        )

        let message2 = InboxMessage(
            queueId: "queue-2", // Different queueId
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: sentAt,
            topics: [],
            type: "",
            opened: false,
            priority: 5,
            properties: [:]
        )

        #expect(message1 != message2)
    }

    @Test("Equality detects property changes")
    func equalityDetectsPropertyChanges() {
        let sentAt = Date()
        let message1 = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: sentAt,
            topics: [],
            type: "",
            opened: false,
            priority: 5,
            properties: [:]
        )

        let message2 = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: sentAt,
            topics: [],
            type: "",
            opened: true, // Only opened changed
            priority: 5,
            properties: [:]
        )

        // Not equal because opened property differs
        #expect(message1 != message2)
    }

    @Test("Equality compares properties dictionary content, not just count")
    func equalityComparesPropertiesDictionaryContent() {
        let sentAt = Date()
        let message1 = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: sentAt,
            topics: [],
            type: "",
            opened: false,
            priority: 5,
            properties: ["theme": "dark"] // Same count, different content
        )

        let message2 = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: sentAt,
            topics: [],
            type: "",
            opened: false,
            priority: 5,
            properties: ["color": "blue"] // Same count, different content
        )

        // Not equal because properties have different keys/values (not just different count)
        #expect(message1 != message2)
    }
}

@Suite("InboxMessageResponse Tests")
struct InboxMessageResponseTest {
    @Test("Failable init returns nil when queueId is missing")
    func failableInitReturnsNilWhenQueueIdMissing() {
        let dictionary: [String: Any] = [
            "deliveryId": "delivery-456",
            "sentAt": "2026-02-09T12:26:42.513994Z"
        ]

        let response = InboxMessageResponse(dictionary: dictionary)

        #expect(response == nil)
    }

    @Test("toDomainModel maps all fields correctly")
    func toDomainModelMapsAllFieldsCorrectly() {
        let dictionary: [String: Any] = [
            "queueId": "queue-123",
            "deliveryId": "delivery-456",
            "expiry": "2026-04-10T12:26:42.51399Z",
            "sentAt": "2026-02-09T12:26:42.513994Z",
            "topics": ["promo"],
            "type": "in-app",
            "opened": true,
            "priority": 5,
            "properties": ["key": "value"]
        ]

        let response = InboxMessageResponse(dictionary: dictionary)!
        let domainModel = response.toDomainModel()

        #expect(domainModel.queueId == "queue-123")
        #expect(domainModel.deliveryId == "delivery-456")
        #expect(domainModel.expiry != nil)
        #expect(domainModel.sentAt != Date())
        #expect(domainModel.topics == ["promo"])
        #expect(domainModel.type == "in-app")
        #expect(domainModel.opened == true)
        #expect(domainModel.priority == 5)
        #expect(domainModel.properties["key"] as? String == "value")
    }

    @Test("toDomainModel succeeds when deliveryId is missing")
    func toDomainModelSucceedsWhenDeliveryIdMissing() {
        let dictionary: [String: Any] = [
            "queueId": "queue-123",
            "sentAt": "2026-02-09T12:26:42.513994Z"
        ]

        let response = InboxMessageResponse(dictionary: dictionary)!
        let domainModel = response.toDomainModel()

        #expect(domainModel.deliveryId == nil)
        #expect(domainModel.expiry == nil)
    }

    @Test("Failable init returns nil when sentAt is missing")
    func failableInitReturnsNilWhenSentAtMissing() {
        let dictionary: [String: Any] = [
            "queueId": "queue-123",
            "deliveryId": "delivery-456"
        ]

        let response = InboxMessageResponse(dictionary: dictionary)

        #expect(response == nil)
    }

    @Test("Failable init returns nil when sentAt is invalid")
    func failableInitReturnsNilWhenSentAtInvalid() {
        let dictionary: [String: Any] = [
            "queueId": "queue-123",
            "sentAt": "invalid-date"
        ]

        let response = InboxMessageResponse(dictionary: dictionary)

        #expect(response == nil)
    }

    @Test("toDomainModel uses default values when optional fields are nil")
    func toDomainModelUsesDefaultValuesWhenOptionalFieldsNil() {
        let dictionary: [String: Any] = [
            "queueId": "queue-123",
            "deliveryId": "delivery-456",
            "sentAt": "2026-02-09T12:26:42.513994Z"
        ]

        let response = InboxMessageResponse(dictionary: dictionary)!
        let domainModel = response.toDomainModel()

        #expect(domainModel.topics == [])
        #expect(domainModel.type == "")
        #expect(domainModel.opened == false)
        #expect(domainModel.priority == nil)
        #expect(domainModel.properties.isEmpty == true)
        #expect(domainModel.expiry == nil)
    }

    @Test("Date parsing with ISO 8601 milliseconds format")
    func dateParsingWithISO8601MillisecondsFormat() {
        let dictionary: [String: Any] = [
            "queueId": "queue-123",
            "expiry": "2026-04-10T12:26:42.513Z",
            "sentAt": "2026-02-09T10:30:15.123Z"
        ]

        let response = InboxMessageResponse(dictionary: dictionary)!
        let domainModel = response.toDomainModel()

        // Verify dates are parsed correctly
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        // Check expiry date
        let expiryComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: domainModel.expiry!
        )
        #expect(expiryComponents.year == 2026)
        #expect(expiryComponents.month == 4)
        #expect(expiryComponents.day == 10)
        #expect(expiryComponents.hour == 12)
        #expect(expiryComponents.minute == 26)
        #expect(expiryComponents.second == 42)

        // Check sentAt date
        let sentAtComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: domainModel.sentAt
        )
        #expect(sentAtComponents.year == 2026)
        #expect(sentAtComponents.month == 2)
        #expect(sentAtComponents.day == 9)
        #expect(sentAtComponents.hour == 10)
        #expect(sentAtComponents.minute == 30)
        #expect(sentAtComponents.second == 15)
    }

    @Test("Date parsing without fractional seconds")
    func dateParsingWithoutFractionalSeconds() {
        let dictionary: [String: Any] = [
            "queueId": "queue-123",
            "expiry": "2026-04-10T12:26:42Z",
            "sentAt": "2026-02-09T10:30:15Z"
        ]

        let response = InboxMessageResponse(dictionary: dictionary)!
        let domainModel = response.toDomainModel()

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        // Check expiry date still parses correctly
        let expiryComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: domainModel.expiry!
        )
        #expect(expiryComponents.year == 2026)
        #expect(expiryComponents.month == 4)
        #expect(expiryComponents.day == 10)
        #expect(expiryComponents.hour == 12)
        #expect(expiryComponents.minute == 26)
        #expect(expiryComponents.second == 42)

        // Check sentAt date
        let sentAtComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: domainModel.sentAt
        )
        #expect(sentAtComponents.year == 2026)
        #expect(sentAtComponents.month == 2)
        #expect(sentAtComponents.day == 9)
        #expect(sentAtComponents.hour == 10)
        #expect(sentAtComponents.minute == 30)
        #expect(sentAtComponents.second == 15)
    }
}
