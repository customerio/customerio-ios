@testable import CioInternalCommon
@testable import CioMessagingInApp
import XCTest

class MessageInboxTest: UnitTest {
    private var messageInbox: MessageInbox!
    private var inAppMessageManagerMock: InAppMessageManagerMock!

    override func setUp() {
        super.setUp()

        inAppMessageManagerMock = InAppMessageManagerMock()
        mockCollection.add(mocks: [inAppMessageManagerMock])

        messageInbox = MessageInbox(
            logger: diGraphShared.logger,
            inAppMessageManager: inAppMessageManagerMock
        )
    }

    override func tearDown() {
        messageInbox = nil
        inAppMessageManagerMock = nil
        super.tearDown()
    }

    func test_inboxAccessibleViaModule_expectNotNil() {
        MessagingInApp.setUpSharedInstanceForIntegrationTest(
            diGraphShared: diGraphShared,
            config: messagingInAppConfigOptions
        )

        let inbox = MessagingInApp.shared.inbox
        XCTAssertNotNil(inbox)
    }

    // MARK: - getMessages tests

    func test_getMessages_whenMessagesExist_expectSortedBySentAtDescending() async {
        let olderDate = Date(timeIntervalSince1970: 1000)
        let newerDate = Date(timeIntervalSince1970: 2000)

        let olderMessage = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: olderDate,
            topics: [],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )
        let newerMessage = InboxMessage(
            queueId: "queue-2",
            deliveryId: "delivery-2",
            expiry: nil,
            sentAt: newerDate,
            topics: [],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )

        let stateWithMessages = InAppMessageState().copy(inboxMessages: Set([olderMessage, newerMessage]))
        inAppMessageManagerMock.underlyingState = stateWithMessages

        let messages = await messageInbox.getMessages(topic: nil)

        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].queueId, "queue-2") // Newer date
        XCTAssertEqual(messages[1].queueId, "queue-1") // Older date
    }

    func test_getMessages_whenTopicProvided_expectFilteredAndSortedByNewestFirst() async {
        let olderDate = Date(timeIntervalSince1970: 1000)
        let middleDate = Date(timeIntervalSince1970: 2000)
        let newerDate = Date(timeIntervalSince1970: 3000)

        let oldPromoMessage = InboxMessage(
            queueId: "queue-1",
            deliveryId: "msg1",
            expiry: nil,
            sentAt: olderDate,
            topics: ["promo"],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )
        let updateMessage = InboxMessage(
            queueId: "queue-2",
            deliveryId: "msg2",
            expiry: nil,
            sentAt: newerDate,
            topics: ["updates"],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )
        let newPromoMessage = InboxMessage(
            queueId: "queue-3",
            deliveryId: "msg3",
            expiry: nil,
            sentAt: middleDate,
            topics: ["promo"],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )

        let stateWithMessages = InAppMessageState().copy(inboxMessages: Set([oldPromoMessage, updateMessage, newPromoMessage]))
        inAppMessageManagerMock.underlyingState = stateWithMessages

        let messages = await messageInbox.getMessages(topic: "promo")

        // Verify filtering: only promo messages returned
        XCTAssertEqual(messages.count, 2)
        let queueIds = Set(messages.map(\.queueId))
        XCTAssertTrue(queueIds.contains("queue-1"))
        XCTAssertTrue(queueIds.contains("queue-3"))

        // Verify sorting: newest first
        XCTAssertEqual(messages[0].deliveryId, "msg3") // middleDate
        XCTAssertEqual(messages[1].deliveryId, "msg1") // olderDate
    }

    func test_getMessages_whenTopicMatchingIsCaseInsensitive_expectCorrectFiltering() async {
        let now = Date()
        let message = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: now,
            topics: ["Promo", "SALE"],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )

        let stateWithMessages = InAppMessageState().copy(inboxMessages: Set([message]))
        inAppMessageManagerMock.underlyingState = stateWithMessages

        // Test lowercase
        let messagesLower = await messageInbox.getMessages(topic: "promo")
        XCTAssertEqual(messagesLower.count, 1)

        // Test uppercase
        let messagesUpper = await messageInbox.getMessages(topic: "SALE")
        XCTAssertEqual(messagesUpper.count, 1)

        // Test mixed case
        let messagesMixed = await messageInbox.getMessages(topic: "SaLe")
        XCTAssertEqual(messagesMixed.count, 1)
    }

    func test_getMessages_whenTopicNotFound_expectEmptyArray() async {
        let now = Date()
        let message = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: now,
            topics: ["promo"],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )

        let stateWithMessages = InAppMessageState().copy(inboxMessages: Set([message]))
        inAppMessageManagerMock.underlyingState = stateWithMessages

        let messages = await messageInbox.getMessages(topic: "nonexistent")

        XCTAssertTrue(messages.isEmpty)
    }
}
