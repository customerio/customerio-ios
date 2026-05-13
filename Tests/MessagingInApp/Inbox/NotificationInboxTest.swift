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
        let initialCallback = expectation(description: "Listener receives initial callback")
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
                if callbackCount == 1 { initialCallback.fulfill() }
            }
            notificationInbox.addChangeListener(listener)
            return listener
        }

        await fulfillment(of: [initialCallback], timeout: 1.0)
        let initialCallbackCount = callbackCount

        // Remove listener, then fence so the @MainActor removal task lands.
        notificationInbox.removeChangeListener(listener)
        await drainMainActor()

        // Push a state change that would have triggered the listener if it were
        // still registered; drain again and confirm the count did not advance.
        let stateWithUpdate = InAppMessageState().copy(inboxMessages: [])
        inAppMessageManagerMock.subscribeReceivedArguments?.subscriber.newState(state: stateWithUpdate)
        await drainMainActor()

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

        // Remove only listener1; fence so the @MainActor removal task lands.
        notificationInbox.removeChangeListener(listener1)
        await drainMainActor()

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
        let bothInitialCallbacks = expectation(description: "Both registrations receive initial callback")
        bothInitialCallbacks.expectedFulfillmentCount = 2
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
                bothInitialCallbacks.fulfill()
            }

            // Register same listener with different topics
            notificationInbox.addChangeListener(listener, topic: "promo")
            notificationInbox.addChangeListener(listener, topic: nil)

            return listener
        }

        await fulfillment(of: [bothInitialCallbacks], timeout: 1.0)
        let initialCallbackCount = callbackCount

        // Remove listener (should remove all registrations); fence the @MainActor removal.
        notificationInbox.removeChangeListener(listener)
        await drainMainActor()

        // Push a state change; the unregistered listener must not be notified.
        let stateWithUpdate = InAppMessageState().copy(inboxMessages: [])
        inAppMessageManagerMock.subscribeReceivedArguments?.subscriber.newState(state: stateWithUpdate)
        await drainMainActor()

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

        // Wait for initial callback to ensure subscription is set up
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

    // MARK: - messages Tests

    func test_messages_expectInitialValueEmitted() async {
        // Given: inbox with messages
        let message1 = createTestMessage(queueId: "msg1")
        let message2 = createTestMessage(queueId: "msg2")
        let stateWithMessages = InAppMessageState().copy(inboxMessages: [message1, message2])
        inAppMessageManagerMock.underlyingState = stateWithMessages

        // When: subscribing to stream and collecting only the first emission.
        var iterator = notificationInbox.messages().makeAsyncIterator()
        let received = await iterator.next()

        // Then: should receive initial messages immediately
        XCTAssertNotNil(received)
        XCTAssertEqual(received?.count, 2)
    }

    func test_messages_withTopic_expectFilteredInitialValue() async {
        // Given: messages with different topics
        let message1 = createTestMessage(queueId: "msg1", topics: ["promo"])
        let message2 = createTestMessage(queueId: "msg2", topics: ["update"])
        let stateWithMessages = InAppMessageState().copy(inboxMessages: [message1, message2])
        inAppMessageManagerMock.underlyingState = stateWithMessages

        // When: subscribing with a topic filter and reading the first emission.
        var iterator = notificationInbox.messages(topic: "promo").makeAsyncIterator()
        let received = await iterator.next()

        // Then: should receive only filtered messages
        XCTAssertEqual(received?.count, 1)
        XCTAssertEqual(received?[0].queueId, "msg1")
    }

    func test_messages_expectOngoingUpdates() async {
        // Given: initial empty state
        let emptyState = InAppMessageState().copy(inboxMessages: [])
        inAppMessageManagerMock.underlyingState = emptyState

        // When: read the initial emission via a direct iterator. The production
        // contract is that `messages()` subscribes BEFORE yielding the first
        // value, so when `next()` returns, the subscription is live.
        var iterator = notificationInbox.messages().makeAsyncIterator()
        let initial = await iterator.next()

        // Then: trigger a state change on every recorded subscriber. The mock can
        // hold both the `messages()` subscriber and the constructor's
        // `subscribeToInboxMessages` subscriber (scheduled via
        // `Task { @MainActor in ... }` at init) — their interleaving is not
        // deterministic, so we fan the new state out to all of them. The
        // constructor's subscriber notifies an (empty) listener list and is a
        // no-op for the AsyncStream; the `messages()` subscriber yields to the
        // iterator.
        let message = createTestMessage(queueId: "msg1")
        let stateWithMessage = InAppMessageState().copy(inboxMessages: [message])
        for invocation in inAppMessageManagerMock.subscribeReceivedInvocations {
            invocation.subscriber.newState(state: stateWithMessage)
        }

        let update = await iterator.next()

        XCTAssertEqual(initial?.count, 0) // Initial empty
        XCTAssertEqual(update?.count, 1) // After update
        XCTAssertEqual(update?[0].queueId, "msg1")
    }

    func test_messages_expectCancellationStopsUpdates() async {
        // Given: an in-flight stream subscription
        let initialState = InAppMessageState().copy(inboxMessages: [])
        inAppMessageManagerMock.underlyingState = initialState

        let initialReceived = expectation(description: "Initial value received")
        var receivedCount = 0
        let task = Task {
            for await _ in notificationInbox.messages() {
                receivedCount += 1
                if receivedCount == 1 { initialReceived.fulfill() }
            }
        }

        await fulfillment(of: [initialReceived], timeout: 1.0)

        // When: cancel and await termination of the for-await loop.
        task.cancel()
        await task.value
        let countAfterCancel = receivedCount

        // Then: a subsequent state change must not deliver another value.
        let message = createTestMessage(queueId: "msg1")
        let stateWithMessage = InAppMessageState().copy(inboxMessages: [message])
        inAppMessageManagerMock.subscribeReceivedArguments?.subscriber.newState(state: stateWithMessage)
        await drainMainActor()

        XCTAssertEqual(receivedCount, countAfterCancel)
    }

    // MARK: - Helper Methods

    /// Fence that returns after all currently-enqueued `@MainActor` work has run.
    /// Replaces fixed-time sleeps when a test needs to observe side-effects of
    /// `Task { @MainActor in ... }` dispatches in the SUT. Two hops cover the
    /// nested-Task pattern used by the inbox (subscriber callback → main-actor
    /// task → listener notify task).
    private func drainMainActor() async {
        for _ in 0 ..< 3 {
            await Task { @MainActor in }.value
        }
    }

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
