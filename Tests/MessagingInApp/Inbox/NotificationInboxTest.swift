@testable import CioInternalCommon
@testable import CioMessagingInAppMocks
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
        guard case .trackClicked(let receivedMessage, let actionName, let actionValue) = inboxAction else {
            XCTFail("Expected trackClicked action")
            return
        }
        XCTAssertEqual(receivedMessage.queueId, message.queueId)
        XCTAssertEqual(receivedMessage.deliveryId, message.deliveryId)
        XCTAssertEqual(actionName, "view_details")
        XCTAssertNil(actionValue)
    }

    func test_trackMessageClicked_withActionValue_expectDispatchesTrackClickedActionWithValue() {
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

        notificationInbox.trackMessageClicked(message: message, actionName: "view_details", actionValue: "https://example.com")

        XCTAssertEqual(inAppMessageManagerMock.dispatchCallsCount, 1)
        guard case .inboxAction(let inboxAction) = inAppMessageManagerMock.dispatchReceivedArguments?.action else {
            XCTFail("Expected inboxAction, got different action")
            return
        }
        guard case .trackClicked(let receivedMessage, let actionName, let actionValue) = inboxAction else {
            XCTFail("Expected trackClicked action")
            return
        }
        XCTAssertEqual(receivedMessage.queueId, message.queueId)
        XCTAssertEqual(actionName, "view_details")
        XCTAssertEqual(actionValue, "https://example.com")
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
        guard case .trackClicked(let receivedMessage, let actionName, _) = inboxAction else {
            XCTFail("Expected trackClicked action")
            return
        }
        XCTAssertEqual(receivedMessage.queueId, message.queueId)
        XCTAssertEqual(receivedMessage.deliveryId, message.deliveryId)
        XCTAssertNil(actionName)
    }

    // MARK: - inbox event listener tests (item 13)

    func test_notifyMessageActionTaken_whenNoListener_expectFalse() {
        let message = makeInboxMessage(queueId: "q-1")
        let handled = notificationInbox.notifyMessageActionTaken(message: message, actionValue: "https://customer.io", actionName: "messageAction")
        XCTAssertFalse(handled)
    }

    func test_notifyMessageActionTaken_whenListenerHandles_expectTrueAndForwardsFields() {
        let listener = InboxEventListenerMock()
        listener.messageActionTakenReturnValue = true
        notificationInbox.setInboxEventListener(listener)

        let message = makeInboxMessage(queueId: "q-1")
        let handled = notificationInbox.notifyMessageActionTaken(message: message, actionValue: "https://customer.io", actionName: "messageAction")

        XCTAssertTrue(handled)
        XCTAssertEqual(listener.messageActionTakenCallsCount, 1)
        XCTAssertEqual(listener.messageActionTakenReceivedArguments?.message.queueId, "q-1")
        XCTAssertEqual(listener.messageActionTakenReceivedArguments?.actionValue, "https://customer.io")
        XCTAssertEqual(listener.messageActionTakenReceivedArguments?.actionName, "messageAction")
    }

    func test_notifyMessageActionTaken_whenListenerDefers_expectFalse() {
        let listener = InboxEventListenerMock()
        listener.messageActionTakenReturnValue = false
        notificationInbox.setInboxEventListener(listener)

        let handled = notificationInbox.notifyMessageActionTaken(message: makeInboxMessage(queueId: "q-1"), actionValue: "", actionName: "messageAction")

        XCTAssertFalse(handled)
        XCTAssertEqual(listener.messageActionTakenCallsCount, 1)
    }

    func test_setInboxEventListener_whenClearedWithNil_expectNoLongerNotified() {
        let listener = InboxEventListenerMock()
        listener.messageActionTakenReturnValue = true
        notificationInbox.setInboxEventListener(listener)
        notificationInbox.setInboxEventListener(nil)

        let handled = notificationInbox.notifyMessageActionTaken(message: makeInboxMessage(queueId: "q-1"), actionValue: "", actionName: "messageAction")

        XCTAssertFalse(handled)
        XCTAssertEqual(listener.messageActionTakenCallsCount, 0)
    }

    // MARK: - observe-only listener callbacks (shown / opened / dismissed)

    func test_markOpenedAndNotify_whenListenerSet_expectInboxMessageOpenedFired() async {
        inAppMessageManagerMock.dispatchReturnValue = Task {}
        let listener = InboxEventListenerMock()
        notificationInbox.setInboxEventListener(listener)

        await notificationInbox.markOpenedAndNotify(message: makeInboxMessage(queueId: "q-1"))
        await flushMainQueue()

        XCTAssertEqual(listener.messageOpenedCallsCount, 1)
        XCTAssertEqual(listener.messageOpenedReceivedArguments?.queueId, "q-1")
        XCTAssertEqual(listener.messageOpenedReceivedArguments?.opened, true)
    }

    func test_markOpenedAndNotify_whenCalledTwiceForSameId_expectFiredOnce() async {
        inAppMessageManagerMock.dispatchReturnValue = Task {}
        let listener = InboxEventListenerMock()
        notificationInbox.setInboxEventListener(listener)

        await notificationInbox.markOpenedAndNotify(message: makeInboxMessage(queueId: "q-1"))
        await notificationInbox.markOpenedAndNotify(message: makeInboxMessage(queueId: "q-1"))
        await flushMainQueue()

        XCTAssertEqual(listener.messageOpenedCallsCount, 1)
    }

    // The store mutation must COMPLETE before the host callback, so a host reading the inbox inside
    // messageOpened/messageDismissed never observes the pre-mutation state. Asserting only that a
    // dispatch happened would not catch a regression — the callback hops to main either way, so it
    // always lands after. Gating the dispatch is what makes this discriminating: while the store
    // work is parked, the listener must not have fired.
    func test_markOpenedAndNotify_expectListenerWaitsForStoreMutation() async {
        let gate = AsyncGate()
        inAppMessageManagerMock.dispatchReturnValue = Task { await gate.wait() }
        let listener = InboxEventListenerMock()
        notificationInbox.setInboxEventListener(listener)

        let call = Task { [notificationInbox, message = makeInboxMessage(queueId: "q-1")] in
            await notificationInbox!.markOpenedAndNotify(message: message)
        }

        // Wait until the store call is parked on the gate. Without this the assertion below could
        // pass simply because the task had not started yet, rather than because of ordering.
        await waitUntil({ self.inAppMessageManagerMock.dispatchCallsCount == 1 }, "the store mark was dispatched")
        await flushMainQueue()
        XCTAssertEqual(listener.messageOpenedCallsCount, 0, "listener fired before the store applied the mark")

        gate.open()
        await call.value
        await flushMainQueue()
        XCTAssertEqual(listener.messageOpenedCallsCount, 1)
    }

    func test_markDismissedAndNotify_whenListenerSet_expectInboxMessageDismissedFired() async {
        inAppMessageManagerMock.dispatchReturnValue = Task {}
        let listener = InboxEventListenerMock()
        notificationInbox.setInboxEventListener(listener)

        await notificationInbox.markDismissedAndNotify(message: makeInboxMessage(queueId: "q-1"))
        await flushMainQueue()

        XCTAssertEqual(listener.messageDismissedCallsCount, 1)
        XCTAssertEqual(listener.messageDismissedReceivedArguments?.queueId, "q-1")
    }

    func test_markDismissedAndNotify_expectListenerWaitsForStoreMutation() async {
        let gate = AsyncGate()
        inAppMessageManagerMock.dispatchReturnValue = Task { await gate.wait() }
        let listener = InboxEventListenerMock()
        notificationInbox.setInboxEventListener(listener)

        let call = Task { [notificationInbox, message = makeInboxMessage(queueId: "q-1")] in
            await notificationInbox!.markDismissedAndNotify(message: message)
        }

        // Wait until the store call is parked on the gate. Without this the assertion below could
        // pass simply because the task had not started yet, rather than because of ordering.
        await waitUntil({ self.inAppMessageManagerMock.dispatchCallsCount == 1 }, "the store delete was dispatched")
        await flushMainQueue()
        XCTAssertEqual(listener.messageDismissedCallsCount, 0, "listener fired before the store applied the delete")

        gate.open()
        await call.value
        await flushMainQueue()
        XCTAssertEqual(listener.messageDismissedCallsCount, 1)
    }

    // The headless mutation API must NOT fire the visual-inbox listener: a host with no overlay
    // mounted should never receive these callbacks (matches Android).
    func test_markMessageOpenedAndDeleted_whenListenerSet_expectNoCallbacks() {
        inAppMessageManagerMock.dispatchReturnValue = Task {}
        let listener = InboxEventListenerMock()
        notificationInbox.setInboxEventListener(listener)

        notificationInbox.markMessageOpened(message: makeInboxMessage(queueId: "q-1"))
        notificationInbox.markMessageDeleted(message: makeInboxMessage(queueId: "q-1"))

        XCTAssertEqual(listener.messageOpenedCallsCount, 0)
        XCTAssertEqual(listener.messageDismissedCallsCount, 0)
    }

    func test_notifyMessageShown_whenCalledTwiceForSameId_expectFiredOnce() {
        let listener = InboxEventListenerMock()
        notificationInbox.setInboxEventListener(listener)
        let message = makeInboxMessage(queueId: "q-1")

        notificationInbox.notifyMessageShown(message: message)
        notificationInbox.notifyMessageShown(message: message)

        XCTAssertEqual(listener.messageShownCallsCount, 1)
        XCTAssertEqual(listener.messageShownReceivedArguments?.queueId, "q-1")
    }

    func test_notifyMessageShown_whenDifferentIds_expectFiredForEach() {
        let listener = InboxEventListenerMock()
        notificationInbox.setInboxEventListener(listener)

        notificationInbox.notifyMessageShown(message: makeInboxMessage(queueId: "q-1"))
        notificationInbox.notifyMessageShown(message: makeInboxMessage(queueId: "q-2"))

        XCTAssertEqual(listener.messageShownCallsCount, 2)
    }

    // MARK: - profile change dedupe reset

    /// Delivers a store state through the subscription the inbox already owns, standing in for what
    /// the reducer produces after an identify, a logout, or a reset.
    ///
    /// Builds the state with the initialiser rather than `copy`, because `copy` coalesces with
    /// `??` and so cannot express clearing an identity back to nil — which is the case under test.
    private func deliverStoreState(userId: String?, anonymousId: String? = nil) async {
        await waitUntil({ self.inAppMessageManagerMock.subscribeReceivedArguments != nil },
            "the inbox subscribed to the store"
        )
        inAppMessageManagerMock.subscribeReceivedArguments?.subscriber.newState(
            state: InAppMessageState(userId: userId, anonymousId: anonymousId)
        )
    }

    func test_profileChange_whenUserLogsOut_expectShownDedupeCleared() async {
        let listener = InboxEventListenerMock()
        notificationInbox.setInboxEventListener(listener)
        let message = makeInboxMessage(queueId: "q-1")

        await deliverStoreState(userId: "user-a")
        notificationInbox.notifyMessageShown(message: message)
        await flushMainQueue()
        XCTAssertEqual(listener.messageShownCallsCount, 1)

        await deliverStoreState(userId: nil)
        notificationInbox.notifyMessageShown(message: message)
        await flushMainQueue()

        XCTAssertEqual(listener.messageShownCallsCount, 2, "logout did not clear the shown dedupe")
    }

    func test_profileChange_whenUserLogsOut_expectOpenedDedupeCleared() async {
        inAppMessageManagerMock.dispatchReturnValue = Task {}
        let listener = InboxEventListenerMock()
        notificationInbox.setInboxEventListener(listener)
        let message = makeInboxMessage(queueId: "q-1")

        await deliverStoreState(userId: "user-a")
        await notificationInbox.markOpenedAndNotify(message: message)
        await flushMainQueue()
        XCTAssertEqual(listener.messageOpenedCallsCount, 1)

        await deliverStoreState(userId: nil)
        await notificationInbox.markOpenedAndNotify(message: message)
        await flushMainQueue()

        XCTAssertEqual(listener.messageOpenedCallsCount, 2, "logout did not clear the opened dedupe")
    }

    // `identify()` switches A → B directly, with no reset on the path, so the switch itself has to
    // clear. Otherwise A → B → A hands A back its own queue ids while they are still deduped and the
    // host silently stops seeing them.
    func test_profileChange_whenProfileSwitchesDirectlyAndBack_expectDedupeClearedEachTime() async {
        let listener = InboxEventListenerMock()
        notificationInbox.setInboxEventListener(listener)
        let message = makeInboxMessage(queueId: "q-1")

        await deliverStoreState(userId: "user-a")
        notificationInbox.notifyMessageShown(message: message)
        await flushMainQueue()
        XCTAssertEqual(listener.messageShownCallsCount, 1)

        // Direct identify A → B, no logout in between.
        await deliverStoreState(userId: "user-b")
        notificationInbox.notifyMessageShown(message: message)
        await flushMainQueue()
        XCTAssertEqual(listener.messageShownCallsCount, 2, "a direct profile switch did not clear the dedupe")

        // ...and back to A, whose ids were last seen two states ago.
        await deliverStoreState(userId: "user-a")
        notificationInbox.notifyMessageShown(message: message)
        await flushMainQueue()
        XCTAssertEqual(listener.messageShownCallsCount, 3, "switching back to a previous profile did not clear the dedupe")
    }

    // An anonymous session never sets `userId`, yet still receives messages (the queue fetch accepts
    // either identity). Its reset is therefore only visible through `anonymousId`.
    func test_profileChange_whenAnonymousSessionResets_expectDedupeCleared() async {
        let listener = InboxEventListenerMock()
        notificationInbox.setInboxEventListener(listener)
        let message = makeInboxMessage(queueId: "q-1")

        await deliverStoreState(userId: nil, anonymousId: "anon-a")
        notificationInbox.notifyMessageShown(message: message)
        await flushMainQueue()
        XCTAssertEqual(listener.messageShownCallsCount, 1)

        await deliverStoreState(userId: nil, anonymousId: nil)
        notificationInbox.notifyMessageShown(message: message)
        await flushMainQueue()

        XCTAssertEqual(listener.messageShownCallsCount, 2, "an anonymous reset did not clear the shown dedupe")
    }

    // The counterpart to the tests above: arriving at a FIRST identity is not a profile change. Every
    // cold launch starts with no identity before identify runs, so clearing there would erase a
    // dedupe that is still valid — and would make the tests above pass for the wrong reason.
    func test_profileChange_whenFirstIdentityArrives_expectDedupeRetained() async {
        let listener = InboxEventListenerMock()
        notificationInbox.setInboxEventListener(listener)
        let message = makeInboxMessage(queueId: "q-1")

        notificationInbox.notifyMessageShown(message: message)
        await flushMainQueue()
        XCTAssertEqual(listener.messageShownCallsCount, 1)

        await deliverStoreState(userId: "user-a")
        notificationInbox.notifyMessageShown(message: message)
        await flushMainQueue()

        XCTAssertEqual(listener.messageShownCallsCount, 1, "the first identify cleared a still-valid dedupe")
    }

    /// Drains the main queue so a listener callback the SDK enqueued via `deliverOnMain` has run
    /// before we assert on it.
    ///
    /// `deliverOnMain` only runs inline when already on the main thread; an `async` test body is not,
    /// so the callback is enqueued instead. Hopping to the main actor lands FIFO behind it, which
    /// makes this deterministic rather than a sleep.
    private func flushMainQueue() async {
        await MainActor.run {}
    }

    /// Polls `condition` until it holds, so a test can wait for work to reach a known point instead of
    /// sleeping for a guessed duration. Fails rather than hanging if it never becomes true.
    private func waitUntil(
        _ condition: () -> Bool,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0 ..< 500 {
            if condition() { return }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 1000000) // 1ms
        }
        XCTFail("timed out waiting until \(message)", file: file, line: line)
    }

    private func makeInboxMessage(queueId: String) -> InboxMessage {
        InboxMessage(queueId: queueId, deliveryId: "d-\(queueId)", expiry: nil, sentAt: Date(), topics: [], type: "", opened: false, priority: nil, properties: [:])
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

        // When: subscribing to stream
        var receivedMessages: [[InboxMessage]] = []
        let task = Task {
            for await messages in notificationInbox.messages() {
                receivedMessages.append(messages)
                if receivedMessages.count >= 1 {
                    break
                }
            }
        }

        // Wait for initial emission
        try? await Task.sleep(nanoseconds: 50000000) // 50ms

        // Then: should receive initial messages immediately
        XCTAssertEqual(receivedMessages.count, 1)
        XCTAssertEqual(receivedMessages[0].count, 2)

        task.cancel()
    }

    func test_messages_withTopic_expectFilteredInitialValue() async {
        // Given: messages with different topics
        let message1 = createTestMessage(queueId: "msg1", topics: ["promo"])
        let message2 = createTestMessage(queueId: "msg2", topics: ["update"])
        let stateWithMessages = InAppMessageState().copy(inboxMessages: [message1, message2])
        inAppMessageManagerMock.underlyingState = stateWithMessages

        // When: subscribing to stream with topic filter
        var receivedMessages: [[InboxMessage]] = []
        let task = Task {
            for await messages in notificationInbox.messages(topic: "promo") {
                receivedMessages.append(messages)
                if receivedMessages.count >= 1 {
                    break
                }
            }
        }

        try? await Task.sleep(nanoseconds: 50000000)

        // Then: should receive only filtered messages
        XCTAssertEqual(receivedMessages.count, 1)
        XCTAssertEqual(receivedMessages[0].count, 1)
        XCTAssertEqual(receivedMessages[0][0].queueId, "msg1")

        task.cancel()
    }

    func test_messages_expectOngoingUpdates() async {
        // Given: initial empty state
        let emptyState = InAppMessageState().copy(inboxMessages: [])
        inAppMessageManagerMock.underlyingState = emptyState

        var receivedMessages: [[InboxMessage]] = []
        let initialExpectation = expectation(description: "Receive initial state")
        let updateExpectation = expectation(description: "Receive state update")

        // When: subscribing to stream
        let task = Task {
            for await messages in notificationInbox.messages() {
                receivedMessages.append(messages)
                if receivedMessages.count == 1 {
                    initialExpectation.fulfill()
                } else if receivedMessages.count == 2 {
                    updateExpectation.fulfill()
                    break
                }
            }
        }

        // Wait for initial emission to ensure stream has started
        await fulfillment(of: [initialExpectation], timeout: 1.0)

        // Wait for subscription to be fully initialized
        // The messages() implementation yields initial state before calling subscribe(),
        // and the subscription itself has async initialization that completes after subscribe() is called.
        // We need this delay to ensure the subscriber is ready to receive state changes.
        try? await Task.sleep(nanoseconds: 100000000) // 100ms

        // Then: trigger state change on all subscribers
        let message = createTestMessage(queueId: "msg1")
        let stateWithMessage = InAppMessageState().copy(inboxMessages: [message])
        for invocation in inAppMessageManagerMock.subscribeReceivedInvocations {
            invocation.subscriber.newState(state: stateWithMessage)
        }

        // Wait for update emission
        await fulfillment(of: [updateExpectation], timeout: 1.0)

        XCTAssertEqual(receivedMessages.count, 2)
        XCTAssertEqual(receivedMessages[0].count, 0) // Initial empty
        XCTAssertEqual(receivedMessages[1].count, 1) // After update

        task.cancel()
    }

    func test_messages_expectCancellationStopsUpdates() async {
        // Given: stream subscription
        let initialState = InAppMessageState().copy(inboxMessages: [])
        inAppMessageManagerMock.underlyingState = initialState

        var receivedCount = 0
        let task = Task {
            for await _ in notificationInbox.messages() {
                receivedCount += 1
            }
        }

        try? await Task.sleep(nanoseconds: 50000000)

        // When: canceling the task
        task.cancel()
        try? await Task.sleep(nanoseconds: 50000000)

        let countAfterCancel = receivedCount

        // Then: no more updates after cancellation
        let message = createTestMessage(queueId: "msg1")
        let stateWithMessage = InAppMessageState().copy(inboxMessages: [message])
        inAppMessageManagerMock.subscribeReceivedArguments?.subscriber.newState(state: stateWithMessage)
        try? await Task.sleep(nanoseconds: 50000000)

        XCTAssertEqual(receivedCount, countAfterCancel)
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

/// Lets a test hold an awaited operation open, so it can assert on the state of the world while that
/// operation is still in flight. Mirrors `GatedInboxNetworkClientStub`'s approach.
private final class AsyncGate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)

    func open() {
        semaphore.signal()
    }

    /// Suspends (without blocking the caller's thread) until `open()` is called.
    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async { [semaphore] in
                semaphore.wait()
                continuation.resume()
            }
        }
    }
}
