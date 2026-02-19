@testable import CioInternalCommon
@testable import CioMessagingInApp
import XCTest

class NotificationInboxTest: UnitTest {
    private var notificationInbox: DefaultNotificationInbox!
    private var inAppMessageManagerMock: InAppMessageManagerMock!

    override func setUp() {
        super.setUp()

        inAppMessageManagerMock = InAppMessageManagerMock()
        mockCollection.add(mocks: [inAppMessageManagerMock])

        // Configure mock to return empty task for subscribe
        inAppMessageManagerMock.subscribeReturnValue = Task {}

        notificationInbox = DefaultNotificationInbox(
            logger: diGraphShared.logger,
            inAppMessageManager: inAppMessageManagerMock
        )
    }

    override func tearDown() {
        notificationInbox = nil
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

        let stateWithMessages = InAppMessageState().copy(inboxMessages: [olderMessage, newerMessage])
        inAppMessageManagerMock.underlyingState = stateWithMessages

        let messages = await notificationInbox.getMessages()

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

        let stateWithMessages = InAppMessageState().copy(inboxMessages: [oldPromoMessage, updateMessage, newPromoMessage])
        inAppMessageManagerMock.underlyingState = stateWithMessages

        let messages = await notificationInbox.getMessages(topic: "promo")

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

        let stateWithMessages = InAppMessageState().copy(inboxMessages: [message])
        inAppMessageManagerMock.underlyingState = stateWithMessages

        // Test lowercase
        let messagesLower = await notificationInbox.getMessages(topic: "promo")
        XCTAssertEqual(messagesLower.count, 1)

        // Test uppercase
        let messagesUpper = await notificationInbox.getMessages(topic: "SALE")
        XCTAssertEqual(messagesUpper.count, 1)

        // Test mixed case
        let messagesMixed = await notificationInbox.getMessages(topic: "SaLe")
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

        let stateWithMessages = InAppMessageState().copy(inboxMessages: [message])
        inAppMessageManagerMock.underlyingState = stateWithMessages

        let messages = await notificationInbox.getMessages(topic: "nonexistent")

        XCTAssertTrue(messages.isEmpty)
    }

    // MARK: - markMessageOpened tests

    func test_markMessageOpened_expectDispatchesUpdateOpenedAction() {
        // Setup mock to return empty task
        inAppMessageManagerMock.dispatchReturnValue = Task {}

        let message = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: Date(),
            topics: [],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )

        notificationInbox.markMessageOpened(message: message)

        XCTAssertEqual(inAppMessageManagerMock.dispatchCallsCount, 1)
        guard case .inboxAction(let inboxAction) = inAppMessageManagerMock.dispatchReceivedArguments?.action else {
            XCTFail("Expected inboxAction, got different action")
            return
        }
        guard case .updateOpened(let receivedMessage, let opened) = inboxAction else {
            XCTFail("Expected updateOpened action")
            return
        }
        XCTAssertEqual(receivedMessage.queueId, message.queueId)
        XCTAssertEqual(receivedMessage.deliveryId, message.deliveryId)
        XCTAssertTrue(opened)
    }

    // MARK: - markMessageUnopened tests

    func test_markMessageUnopened_expectDispatchesUpdateOpenedAction() {
        // Setup mock to return empty task
        inAppMessageManagerMock.dispatchReturnValue = Task {}

        let message = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: Date(),
            topics: [],
            type: "",
            opened: true,
            priority: nil,
            properties: [:]
        )

        notificationInbox.markMessageUnopened(message: message)

        XCTAssertEqual(inAppMessageManagerMock.dispatchCallsCount, 1)
        guard case .inboxAction(let inboxAction) = inAppMessageManagerMock.dispatchReceivedArguments?.action else {
            XCTFail("Expected inboxAction, got different action")
            return
        }
        guard case .updateOpened(let receivedMessage, let opened) = inboxAction else {
            XCTFail("Expected updateOpened action")
            return
        }
        XCTAssertEqual(receivedMessage.queueId, message.queueId)
        XCTAssertEqual(receivedMessage.deliveryId, message.deliveryId)
        XCTAssertFalse(opened)
    }

    // MARK: - markMessageDeleted tests

    func test_markMessageDeleted_expectDispatchesDeleteMessageAction() {
        // Setup mock to return empty task
        inAppMessageManagerMock.dispatchReturnValue = Task {}

        let message = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: Date(),
            topics: [],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )

        notificationInbox.markMessageDeleted(message: message)

        XCTAssertEqual(inAppMessageManagerMock.dispatchCallsCount, 1)
        guard case .inboxAction(let inboxAction) = inAppMessageManagerMock.dispatchReceivedArguments?.action else {
            XCTFail("Expected inboxAction, got different action")
            return
        }
        guard case .deleteMessage(let receivedMessage) = inboxAction else {
            XCTFail("Expected deleteMessage action")
            return
        }
        XCTAssertEqual(receivedMessage.queueId, message.queueId)
        XCTAssertEqual(receivedMessage.deliveryId, message.deliveryId)
    }

    // MARK: - trackMessageClicked tests

    func test_trackMessageClicked_withActionName_expectDispatchesTrackClickedAction() {
        // Setup mock to return empty task
        inAppMessageManagerMock.dispatchReturnValue = Task {}

        let message = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: Date(),
            topics: [],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )

        notificationInbox.trackMessageClicked(message: message, actionName: "view_details")

        XCTAssertEqual(inAppMessageManagerMock.dispatchCallsCount, 1)
        guard case .inboxAction(let inboxAction) = inAppMessageManagerMock.dispatchReceivedArguments?.action else {
            XCTFail("Expected inboxAction, got different action")
            return
        }
        guard case .trackClicked(let receivedMessage, let actionName) = inboxAction else {
            XCTFail("Expected trackClicked action")
            return
        }
        XCTAssertEqual(receivedMessage.queueId, message.queueId)
        XCTAssertEqual(receivedMessage.deliveryId, message.deliveryId)
        XCTAssertEqual(actionName, "view_details")
    }

    func test_trackMessageClicked_withoutActionName_expectDispatchesTrackClickedAction() {
        // Setup mock to return empty task
        inAppMessageManagerMock.dispatchReturnValue = Task {}

        let message = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: Date(),
            topics: [],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )

        notificationInbox.trackMessageClicked(message: message, actionName: nil)

        XCTAssertEqual(inAppMessageManagerMock.dispatchCallsCount, 1)
        guard case .inboxAction(let inboxAction) = inAppMessageManagerMock.dispatchReceivedArguments?.action else {
            XCTFail("Expected inboxAction, got different action")
            return
        }
        guard case .trackClicked(let receivedMessage, let actionName) = inboxAction else {
            XCTFail("Expected trackClicked action")
            return
        }
        XCTAssertEqual(receivedMessage.queueId, message.queueId)
        XCTAssertEqual(receivedMessage.deliveryId, message.deliveryId)
        XCTAssertNil(actionName)
    }

    // MARK: - addChangeListener tests

    func test_addChangeListener_expectImmediateCallbackWithCurrentMessages() async {
        let expectation = expectation(description: "Listener receives immediate callback")

        let message = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: Date(),
            topics: [],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )

        let stateWithMessages = InAppMessageState().copy(inboxMessages: [message])
        inAppMessageManagerMock.underlyingState = stateWithMessages

        let listener = await MainActor.run {
            let listener = TestNotificationInboxChangeListener()
            listener.onMessagesChangedClosure = { messages in
                XCTAssertEqual(messages.count, 1)
                XCTAssertEqual(messages[0].queueId, "queue-1")
                expectation.fulfill()
            }
            notificationInbox.addChangeListener(listener)
            return listener
        }

        await fulfillment(of: [expectation], timeout: 1.0)

        // Keep listener alive
        _ = listener
    }

    func test_addChangeListener_withTopic_expectFilteredMessagesInImmediateCallback() async {
        let expectation = expectation(description: "Listener receives filtered messages")

        let promoMessage = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: Date(),
            topics: ["promo"],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )
        let updateMessage = InboxMessage(
            queueId: "queue-2",
            deliveryId: "delivery-2",
            expiry: nil,
            sentAt: Date(),
            topics: ["updates"],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )

        let stateWithMessages = InAppMessageState().copy(inboxMessages: [promoMessage, updateMessage])
        inAppMessageManagerMock.underlyingState = stateWithMessages

        let listener = await MainActor.run {
            let listener = TestNotificationInboxChangeListener()
            listener.onMessagesChangedClosure = { messages in
                XCTAssertEqual(messages.count, 1)
                XCTAssertEqual(messages[0].queueId, "queue-1")
                XCTAssertEqual(messages[0].topics, ["promo"])
                expectation.fulfill()
            }
            notificationInbox.addChangeListener(listener, topic: "promo")
            return listener
        }

        await fulfillment(of: [expectation], timeout: 1.0)

        // Keep listener alive
        _ = listener
    }

    func test_addChangeListener_withEmptyState_expectEmptyArrayCallback() async {
        let expectation = expectation(description: "Listener receives empty array")

        inAppMessageManagerMock.underlyingState = InAppMessageState()

        let listener = await MainActor.run {
            let listener = TestNotificationInboxChangeListener()
            listener.onMessagesChangedClosure = { messages in
                XCTAssertTrue(messages.isEmpty)
                expectation.fulfill()
            }
            notificationInbox.addChangeListener(listener)
            return listener
        }

        await fulfillment(of: [expectation], timeout: 1.0)

        // Keep listener alive
        _ = listener
    }

    func test_addChangeListener_multipleListeners_expectBothReceiveCallbacks() async {
        let expectation1 = expectation(description: "Listener 1 receives callback")
        let expectation2 = expectation(description: "Listener 2 receives callback")

        let message = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: Date(),
            topics: [],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )

        let stateWithMessages = InAppMessageState().copy(inboxMessages: [message])
        inAppMessageManagerMock.underlyingState = stateWithMessages

        let (listener1, listener2) = await MainActor.run {
            let listener1 = TestNotificationInboxChangeListener()
            let listener2 = TestNotificationInboxChangeListener()

            listener1.onMessagesChangedClosure = { messages in
                XCTAssertEqual(messages.count, 1)
                expectation1.fulfill()
            }

            listener2.onMessagesChangedClosure = { messages in
                XCTAssertEqual(messages.count, 1)
                expectation2.fulfill()
            }

            notificationInbox.addChangeListener(listener1)
            notificationInbox.addChangeListener(listener2)

            return (listener1, listener2)
        }

        await fulfillment(of: [expectation1, expectation2], timeout: 1.0)

        // Keep listeners alive
        _ = (listener1, listener2)
    }

    func test_addChangeListener_multipleListenersWithDifferentTopics_expectCorrectFiltering() async {
        let expectation1 = expectation(description: "Promo listener receives promo messages")
        let expectation2 = expectation(description: "Updates listener receives update messages")

        let promoMessage = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: Date(),
            topics: ["promo"],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )
        let updateMessage = InboxMessage(
            queueId: "queue-2",
            deliveryId: "delivery-2",
            expiry: nil,
            sentAt: Date(),
            topics: ["updates"],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )

        let stateWithMessages = InAppMessageState().copy(inboxMessages: [promoMessage, updateMessage])
        inAppMessageManagerMock.underlyingState = stateWithMessages

        let (listener1, listener2) = await MainActor.run {
            let listener1 = TestNotificationInboxChangeListener()
            let listener2 = TestNotificationInboxChangeListener()

            listener1.onMessagesChangedClosure = { messages in
                XCTAssertEqual(messages.count, 1)
                XCTAssertEqual(messages[0].topics, ["promo"])
                expectation1.fulfill()
            }

            listener2.onMessagesChangedClosure = { messages in
                XCTAssertEqual(messages.count, 1)
                XCTAssertEqual(messages[0].topics, ["updates"])
                expectation2.fulfill()
            }

            notificationInbox.addChangeListener(listener1, topic: "promo")
            notificationInbox.addChangeListener(listener2, topic: "updates")

            return (listener1, listener2)
        }

        await fulfillment(of: [expectation1, expectation2], timeout: 1.0)

        // Keep listeners alive
        _ = (listener1, listener2)
    }

    // MARK: - removeChangeListener tests

    func test_removeChangeListener_expectListenerStopsReceivingUpdates() async {
        var callbackCount = 0

        let message = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: Date(),
            topics: [],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )

        let stateWithMessages = InAppMessageState().copy(inboxMessages: [message])
        inAppMessageManagerMock.underlyingState = stateWithMessages

        let listener = await MainActor.run {
            let listener = TestNotificationInboxChangeListener()
            listener.onMessagesChangedClosure = { _ in
                callbackCount += 1
            }
            notificationInbox.addChangeListener(listener)
            return listener
        }

        // Wait for initial callback
        try? await Task.sleep(nanoseconds: 100000000) // 100ms

        let initialCallbackCount = callbackCount
        XCTAssertGreaterThan(initialCallbackCount, 0, "Should have received initial callback")

        // Remove listener
        notificationInbox.removeChangeListener(listener)

        // Wait to ensure no more callbacks
        try? await Task.sleep(nanoseconds: 100000000) // 100ms

        XCTAssertEqual(callbackCount, initialCallbackCount, "Should not receive more callbacks after removal")
    }

    func test_removeChangeListener_withMultipleListeners_expectOnlyTargetListenerRemoved() async {
        let expectation1 = expectation(description: "Listener 1 receives initial callback")
        let expectation2 = expectation(description: "Listener 2 receives initial callback")
        var listener1CallCount = 0
        var listener2CallCount = 0

        let message = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: Date(),
            topics: [],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )

        let stateWithMessages = InAppMessageState().copy(inboxMessages: [message])
        inAppMessageManagerMock.underlyingState = stateWithMessages

        let (listener1, listener2) = await MainActor.run {
            let listener1 = TestNotificationInboxChangeListener()
            let listener2 = TestNotificationInboxChangeListener()

            listener1.onMessagesChangedClosure = { _ in
                listener1CallCount += 1
                expectation1.fulfill()
            }

            listener2.onMessagesChangedClosure = { _ in
                listener2CallCount += 1
                expectation2.fulfill()
            }

            notificationInbox.addChangeListener(listener1)
            notificationInbox.addChangeListener(listener2)

            return (listener1, listener2)
        }

        await fulfillment(of: [expectation1, expectation2], timeout: 1.0)

        // Remove only listener1
        notificationInbox.removeChangeListener(listener1)

        // Wait to ensure listener1 doesn't receive more callbacks
        try? await Task.sleep(nanoseconds: 100000000) // 100ms

        // Both should have been called once (initial callback)
        XCTAssertEqual(listener1CallCount, 1, "Listener 1 should only receive initial callback")
        XCTAssertEqual(listener2CallCount, 1, "Listener 2 should still be active")
    }

    func test_removeChangeListener_canBeCalledFromAnyThread_expectNoError() async {
        inAppMessageManagerMock.underlyingState = InAppMessageState()

        let listener = await MainActor.run {
            let listener = TestNotificationInboxChangeListener()
            notificationInbox.addChangeListener(listener)
            return listener
        }

        // Call removeChangeListener from background thread
        await Task.detached {
            self.notificationInbox.removeChangeListener(listener)
        }.value

        // No assertion needed - test passes if no crash occurs
    }

    func test_removeChangeListener_removesAllRegistrationsOfListener_expectNoCallbacks() async {
        var callbackCount = 0

        let message = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: Date(),
            topics: ["promo"],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )

        let stateWithMessages = InAppMessageState().copy(inboxMessages: [message])
        inAppMessageManagerMock.underlyingState = stateWithMessages

        let listener = await MainActor.run {
            let listener = TestNotificationInboxChangeListener()
            listener.onMessagesChangedClosure = { _ in
                callbackCount += 1
            }

            // Register same listener with different topics
            notificationInbox.addChangeListener(listener, topic: "promo")
            notificationInbox.addChangeListener(listener, topic: nil)

            return listener
        }

        // Wait for initial callbacks
        try? await Task.sleep(nanoseconds: 100000000) // 100ms

        XCTAssertGreaterThan(callbackCount, 0, "Should have received initial callbacks")

        let initialCallbackCount = callbackCount

        // Remove listener (should remove all registrations)
        notificationInbox.removeChangeListener(listener)

        // Wait to ensure no more callbacks
        try? await Task.sleep(nanoseconds: 100000000) // 100ms

        XCTAssertEqual(callbackCount, initialCallbackCount, "Should not receive more callbacks after removal")
    }

    func test_addChangeListener_receivesOngoingCallbacksWhenStateChanges() async {
        let initialExpectation = expectation(description: "Listener receives initial callback")
        let updateExpectation = expectation(description: "Listener receives update callback")
        var callbackCount = 0
        var receivedMessageCounts: [Int] = []

        // Create test messages
        let message1 = createTestMessage(queueId: "queue-1")
        let message2 = createTestMessage(queueId: "queue-2")

        // Start with 2 messages
        inAppMessageManagerMock.underlyingState = InAppMessageState().copy(
            inboxMessages: [message1, message2]
        )

        let listener = await MainActor.run {
            let listener = TestNotificationInboxChangeListener()
            listener.onMessagesChangedClosure = { messages in
                callbackCount += 1
                receivedMessageCounts.append(messages.count)
                if callbackCount == 1 {
                    initialExpectation.fulfill()
                } else if callbackCount == 2 {
                    updateExpectation.fulfill()
                }
            }
            notificationInbox.addChangeListener(listener)
            return listener
        }

        // Wait for initial callback
        await fulfillment(of: [initialExpectation], timeout: 1.0)
        XCTAssertEqual(callbackCount, 1, "Should receive initial callback")
        XCTAssertEqual(receivedMessageCounts[0], 2, "Initial callback should have 2 messages")

        // Simulate state change: Delete a message
        let stateWithOneMessage = InAppMessageState().copy(inboxMessages: [message1])
        inAppMessageManagerMock.subscribeReceivedArguments?.subscriber.newState(state: stateWithOneMessage)

        // Wait for update callback
        await fulfillment(of: [updateExpectation], timeout: 1.0)
        XCTAssertEqual(callbackCount, 2, "Should receive update callback")
        XCTAssertEqual(receivedMessageCounts[1], 1, "Update callback should have 1 message after delete")

        // Keep listener alive
        _ = listener
    }

    // MARK: - Helper Methods

    private func createTestMessage(
        queueId: String,
        deliveryId: String? = nil,
        topics: [String] = []
    ) -> InboxMessage {
        InboxMessage(
            queueId: queueId,
            deliveryId: deliveryId ?? "delivery-\(queueId)",
            expiry: nil,
            sentAt: Date(),
            topics: topics,
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )
    }
}

// MARK: - Test Helper Classes

@MainActor
private class TestNotificationInboxChangeListener: NotificationInboxChangeListener {
    var onMessagesChangedClosure: (([InboxMessage]) -> Void)?

    func onMessagesChanged(messages: [InboxMessage]) {
        onMessagesChangedClosure?(messages)
    }
}
