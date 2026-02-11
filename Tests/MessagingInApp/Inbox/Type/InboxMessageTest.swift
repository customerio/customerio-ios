@testable import CioInternalCommon
@testable import CioMessagingInApp
import Foundation
import Testing

@Suite("InboxMessage Tests")
struct InboxMessageTest {
    @Test("Hashable uses queueId for deduplication")
    func hashableUsesQueueIdForDeduplication() {
        let sentAt = Date()
        // message1 and message2 have same queueId - should be dedup'd
        let message1 = InboxMessage(queueId: "queue-1", deliveryId: "delivery-1", expiry: nil, sentAt: sentAt, topics: [], type: "", opened: false, priority: 5, properties: [:])
        let message2 = InboxMessage(queueId: "queue-1", deliveryId: "delivery-2", expiry: nil, sentAt: sentAt, topics: [], type: "", opened: false, priority: 5, properties: [:])
        let message3 = InboxMessage(queueId: "queue-2", deliveryId: "delivery-1", expiry: nil, sentAt: sentAt, topics: [], type: "", opened: false, priority: 5, properties: [:])

        var set = Set<InboxMessage>()
        set.insert(message1)
        set.insert(message2)
        set.insert(message3)

        // message1 and message2 have same queueId (same hash), so only 2 unique messages in Set
        #expect(set.count == 2)
    }
}

@Suite("InboxMessageResponse Tests")
struct InboxMessageResponseTest {
    @Test("toDomainModel maps all fields correctly")
    func toDomainModelMapsAllFieldsCorrectly() {
        let response = InboxMessageResponse(
            queueId: "queue-123",
            deliveryId: "delivery-456",
            expiry: "2026-04-10T12:26:42.51399Z",
            sentAt: "2026-02-09T12:26:42.513994Z",
            topics: ["promo"],
            type: "in-app",
            opened: true,
            priority: 5,
            properties: ["key": "value"]
        )

        let domainModel = response.toDomainModel()

        #expect(domainModel != nil)
        #expect(domainModel?.queueId == "queue-123")
        #expect(domainModel?.deliveryId == "delivery-456")
        #expect(domainModel?.expiry != nil)
        #expect(domainModel?.sentAt != nil)
        #expect(domainModel?.topics == ["promo"])
        #expect(domainModel?.type == "in-app")
        #expect(domainModel?.opened == true)
        #expect(domainModel?.priority == 5)
        #expect(domainModel?.properties["key"] as? String == "value")
    }

    @Test("toDomainModel returns nil when queueId is missing")
    func toDomainModelReturnsNilWhenQueueIdMissing() {
        let response = InboxMessageResponse(
            queueId: nil,
            deliveryId: "delivery-456",
            expiry: nil,
            sentAt: "2026-02-09T12:26:42.513994Z",
            topics: nil,
            type: nil,
            opened: nil,
            priority: nil,
            properties: nil
        )

        #expect(response.toDomainModel() == nil)
    }

    @Test("toDomainModel succeeds when deliveryId is missing")
    func toDomainModelSucceedsWhenDeliveryIdMissing() {
        let response = InboxMessageResponse(
            queueId: "queue-123",
            deliveryId: nil,
            expiry: nil,
            sentAt: "2026-02-09T12:26:42.513994Z",
            topics: nil,
            type: nil,
            opened: nil,
            priority: nil,
            properties: nil
        )

        let domainModel = response.toDomainModel()

        #expect(domainModel != nil)
        #expect(domainModel?.deliveryId == nil)
        #expect(domainModel?.expiry == nil)
    }

    @Test("toDomainModel uses default values when optional fields are nil")
    func toDomainModelUsesDefaultValuesWhenOptionalFieldsNil() {
        let response = InboxMessageResponse(
            queueId: "queue-123",
            deliveryId: "delivery-456",
            expiry: nil,
            sentAt: nil,
            topics: nil,
            type: nil,
            opened: nil,
            priority: nil,
            properties: nil
        )

        let domainModel = response.toDomainModel()

        #expect(domainModel != nil)
        #expect(domainModel?.topics == [])
        #expect(domainModel?.type == "")
        #expect(domainModel?.opened == false)
        #expect(domainModel?.priority == nil)
        #expect(domainModel?.properties.isEmpty == true)
        #expect(domainModel?.expiry == nil)

        // sentAt should default to current time (within 1 second)
        let now = Date()
        let timeDiff = abs((domainModel?.sentAt.timeIntervalSince1970 ?? 0) - now.timeIntervalSince1970)
        #expect(timeDiff < 1.0)
    }

    @Test("Date parsing with ISO 8601 milliseconds format")
    func dateParsingWithISO8601MillisecondsFormat() {
        let response = InboxMessageResponse(
            queueId: "queue-123",
            deliveryId: nil,
            expiry: "2026-04-10T12:26:42.513Z",
            sentAt: "2026-02-09T10:30:15.123Z",
            topics: nil,
            type: nil,
            opened: nil,
            priority: nil,
            properties: nil
        )

        let domainModel = response.toDomainModel()

        #expect(domainModel != nil)

        // Verify dates are parsed correctly
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        // Check expiry date
        let expiryComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: domainModel!.expiry!
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
            from: domainModel!.sentAt
        )
        #expect(sentAtComponents.year == 2026)
        #expect(sentAtComponents.month == 2)
        #expect(sentAtComponents.day == 9)
        #expect(sentAtComponents.hour == 10)
        #expect(sentAtComponents.minute == 30)
        #expect(sentAtComponents.second == 15)
    }
}
