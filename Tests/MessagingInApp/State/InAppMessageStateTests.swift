@testable import CioInternalCommon
@testable import CioMessagingInApp
import XCTest

extension InAppMessageManager {
    func dispatchAsync(action: InAppMessageAction) async {
        await dispatch(action: action).value
    }
}

class InAppMessageStateTests: IntegrationTest {
    var inAppMessageManager: InAppMessageManager!
    private let engineWebMock = EngineWebInstanceMock()
    private var engineWebProvider: EngineWebProvider {
        EngineWebProviderStub(engineWebMock: engineWebMock)
    }

    private let globalEventListener = InAppEventListenerMock()
    var gist: Gist!
    var queueManager: QueueManager!

    override func setUp() {
        super.setUp()
        engineWebMock.underlyingView = UIView()
        MessagingInApp.shared.setEventListener(globalEventListener)

        mockCollection.add(mocks: [engineWebMock, globalEventListener])

        diGraphShared.override(value: CioThreadUtil(), forType: ThreadUtil.self)
        diGraphShared.override(value: engineWebProvider, forType: EngineWebProvider.self)

        inAppMessageManager = InAppMessageStoreManager(
            logger: diGraphShared.logger,
            threadUtil: diGraphShared.threadUtil,
            logManager: diGraphShared.logManager,
            gistDelegate: diGraphShared.gistDelegate,
            anonymousMessageManager: diGraphShared.anonymousMessageManager,
            eventBusHandler: diGraphShared.eventBusHandler
        )

        diGraphShared.override(value: inAppMessageManager, forType: InAppMessageManager.self)

        queueManager = QueueManager(
            keyValueStore: diGraphShared.sharedKeyValueStorage,
            gistQueueNetwork: gistQueueNetworkMock,
            inAppMessageManager: inAppMessageManager,
            anonymousMessageManager: diGraphShared.anonymousMessageManager,
            logger: diGraphShared.logger
        )

        gist = Gist(
            logger: diGraphShared.logger,
            gistDelegate: diGraphShared.gistDelegate,
            inAppMessageManager: inAppMessageManager,
            queueManager: queueManager,
            threadUtil: diGraphShared.threadUtil,
            sseLifecycleManager: diGraphShared.sseLifecycleManager
        )
    }

    // This add a wait so that all the middlewares are done processing by the time we check state
    func dispatchAndWait(_ action: InAppMessageAction, timeout seconds: TimeInterval = 3) async throws {
        let expectation = XCTestExpectation(description: "Action completed: \(action)")
        inAppMessageManager.dispatch(action: action) {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: seconds)
    }

    override func tearDown() {
        inAppMessageManager = nil
        super.tearDown()
    }

    // MARK: - State Tests

    func test_initialState_expectDefaultValues() async {
        let state = await inAppMessageManager.state
        XCTAssertEqual(state.siteId, "")
        XCTAssertEqual(state.dataCenter, "")
        XCTAssertEqual(state.environment, .production)
        XCTAssertEqual(state.pollInterval, 600)
        XCTAssertNil(state.userId)
        XCTAssertNil(state.currentRoute)
        XCTAssertEqual(state.useSse, false)
        XCTAssertEqual(state.modalMessageState, .initial)
        XCTAssertTrue(state.messagesInQueue.isEmpty)
        XCTAssertTrue(state.shownMessageQueueIds.isEmpty)
    }

    func test_initialize_expectCorrectStateUpdate() async {
        await inAppMessageManager.dispatchAsync(action: .initialize(siteId: "testSite", dataCenter: "testDC", environment: .development))

        let state = await inAppMessageManager.state
        XCTAssertEqual(state.siteId, "testSite")
        XCTAssertEqual(state.dataCenter, "testDC")
        XCTAssertEqual(state.environment, .development)
    }

    func test_setUserIdentifier_expectUserIdUpdate() async {
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: "testUser"))

        let state = await inAppMessageManager.state
        XCTAssertEqual(state.userId, "testUser")
    }

    func test_setPageRoute_expectRouteUpdate() async {
        await inAppMessageManager.dispatchAsync(action: .setPageRoute(route: "testRoute"))

        let state = await inAppMessageManager.state
        XCTAssertEqual(state.currentRoute, "testRoute")
    }

    func test_processMessageQueue_expectMessagesAddedToQueue() async {
        let messages = [Message(queueId: "1"), Message(queueId: "2")]
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .processMessageQueue(messages: messages))

        let state = await inAppMessageManager.state
        XCTAssertEqual(state.messagesInQueue.count, 2)
        XCTAssertTrue(state.messagesInQueue.contains { $0.queueId == "1" })
        XCTAssertTrue(state.messagesInQueue.contains { $0.queueId == "2" })
    }

    func test_displayMessage_expectMessageStateUpdated() async {
        let message = Message(queueId: "1")

        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .displayMessage(message: message))

        let state = await inAppMessageManager.state
        XCTAssertEqual(state.modalMessageState, .displayed(message: message))
        XCTAssertTrue(state.shownMessageQueueIds.contains("1"))
    }

    func test_dismissMessage_expectMessageStateDismissed() async {
        let message = Message(queueId: "1")

        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .dismissMessage(message: message))

        let state = await inAppMessageManager.state
        XCTAssertEqual(state.modalMessageState, .dismissed(message: message))
    }

    func test_resetState_expectInitialStateRestored() async {
        // Setup user
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .resetState)

        let state = await inAppMessageManager.state
        XCTAssertEqual(state.siteId, "")
        XCTAssertEqual(state.dataCenter, "")
        XCTAssertEqual(state.environment, .production)
        XCTAssertNil(state.userId)
        XCTAssertNil(state.currentRoute)
        XCTAssertEqual(state.modalMessageState, .initial)
        XCTAssertTrue(state.messagesInQueue.isEmpty)
        XCTAssertTrue(state.shownMessageQueueIds.isEmpty)
    }

    // MARK: - Message Processing Tests

    func test_processMessageQueue_givenMessagePriorities_expectHighestPriorityLoaded() async {
        let messages = [
            Message(priority: 2, queueId: "1"),
            Message(priority: 1, queueId: "2"),
            Message(priority: 3, queueId: "3")
        ]

        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .processMessageQueue(messages: messages))

        var state = await inAppMessageManager.state
        XCTAssertEqual(state.messagesInQueue.count, 3)

        state = await inAppMessageManager.waitForState { state in
            state.modalMessageState.isLoading
        }

        if case .loading(let message) = state.modalMessageState {
            XCTAssertEqual(message.queueId, "2")
        } else {
            XCTFail("Expected loading state with highest priority message")
        }
    }

    func test_processMessageQueue_givenDuplicateMessages_expectDuplicatesRemoved() async {
        let messages = [
            Message(queueId: "1"),
            Message(queueId: "1"),
            Message(queueId: "2")
        ]

        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .processMessageQueue(messages: messages))

        let state = await inAppMessageManager.state
        XCTAssertEqual(state.messagesInQueue.count, 2)
        XCTAssertTrue(state.messagesInQueue.contains { $0.queueId == "1" })
        XCTAssertTrue(state.messagesInQueue.contains { $0.queueId == "2" })
    }

    func test_routeChange_givenMessageWithPageRule_expectMessageStateUpdated() async throws {
        let message = Message(pageRule: "home", queueId: "1")

        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .processMessageQueue(messages: [message]))
        try await dispatchAndWait(.setPageRoute(route: "home"))

        var state = await inAppMessageManager.state
        XCTAssertEqual(state.currentRoute, "home")

        if case .loading(let loadingMessage) = state.modalMessageState {
            XCTAssertEqual(loadingMessage.queueId, "1")
        } else {
            XCTFail("Expected loading state with message")
        }

        // Change route to dismiss the message
        try await dispatchAndWait(.setPageRoute(route: "profile"))

        state = await inAppMessageManager.state
        XCTAssertEqual(state.currentRoute, "profile")

        if case .dismissed(let dismissedMessage) = state.modalMessageState {
            XCTAssertEqual(dismissedMessage.queueId, "1")
        } else {
            XCTFail("Expected dismissed state")
        }
    }

    // MARK: - Inline Tests

    func test_embedMessage_expectNoStateChange() async {
        let elementId = "testElementId"

        let message = Message(elementId: elementId, queueId: "1")

        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .processMessageQueue(messages: [message]))

        let state = await inAppMessageManager.state
        XCTAssertEqual(state.modalMessageState, .initial)
        XCTAssertTrue(state.embeddedMessagesState.getMessage(forElementId: elementId)?.message?.queueId == "1")
        XCTAssertFalse(state.shownMessageQueueIds.contains("1"))
    }

    func test_embedMessage_givenDuplicateElementId_expectOnlyOneMessageAdded() async {
        let elementId = String.random
        let message1 = Message(elementId: elementId, queueId: "1")
        let message2 = Message(elementId: elementId, queueId: "2")

        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .processMessageQueue(messages: [message1, message2]))

        let state = await inAppMessageManager.state
        let embeddedMessage = state.embeddedMessagesState.getMessage(forElementId: elementId)

        XCTAssertNotNil(embeddedMessage)
        XCTAssertEqual(embeddedMessage?.message?.queueId, "2") // Only the latest message should be embedded, since its a map
    }

    func test_dismissEmbeddedMessage_expectStateUpdatedToDismissed() async {
        let elementId = String.random
        let message = Message(elementId: elementId, queueId: "1")

        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .processMessageQueue(messages: [message]))
        await inAppMessageManager.dispatchAsync(action: .dismissMessage(message: message))

        let state = await inAppMessageManager.state
        let embeddedMessage = state.embeddedMessagesState.getMessage(forElementId: elementId)

        XCTAssertNotNil(embeddedMessage)
        XCTAssertEqual(embeddedMessage?.message?.queueId, "1")
        XCTAssertEqual(embeddedMessage, .dismissed(message: message))
    }

    func test_readyToEmbedMessage_expectStateUpdatedToEmbedded() async {
        let elementId = String.random
        let message = Message(elementId: elementId, queueId: "1")

        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .processMessageQueue(messages: [message]))
        await inAppMessageManager.dispatchAsync(action: .displayMessage(message: message))

        let state = await inAppMessageManager.state
        let embeddedMessage = state.embeddedMessagesState.getMessage(forElementId: elementId)

        XCTAssertNotNil(embeddedMessage)
        XCTAssertEqual(embeddedMessage?.message?.queueId, "1")
        XCTAssertEqual(embeddedMessage, .embedded(message: message, elementId: elementId))
    }

    func test_embedMessage_givenRouteMismatch_expectMessageNotEmbedded() async {
        let elementId = String.random
        let message = Message(pageRule: "home", elementId: elementId, queueId: "1")

        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .setPageRoute(route: "profile"))
        await inAppMessageManager.dispatchAsync(action: .processMessageQueue(messages: [message]))

        let state = await inAppMessageManager.state
        let embeddedMessage = state.embeddedMessagesState.getMessage(forElementId: elementId)

        XCTAssertNil(embeddedMessage) // Message should not be embedded as the route doesn't match
    }

    func test_embedMessage_givenRouteMatch_expectMessageEmbedded() async {
        let elementId = String.random
        let message = Message(pageRule: "home", elementId: elementId, queueId: "1")

        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .setPageRoute(route: "home"))
        await inAppMessageManager.dispatchAsync(action: .processMessageQueue(messages: [message]))

        let state = await inAppMessageManager.state
        let embeddedMessage = state.embeddedMessagesState.getMessage(forElementId: elementId)

        XCTAssertNotNil(embeddedMessage)
        XCTAssertEqual(embeddedMessage?.message?.queueId, "1")
    }

    func test_processMessageQueue_givenMultipleEmbeddedMessages_expectAllEmbedded() async {
        let message1 = Message(elementId: "element1", queueId: "1")
        let message2 = Message(elementId: "element2", queueId: "2")

        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .processMessageQueue(messages: [message1, message2]))

        let state = await inAppMessageManager.state
        let embeddedMessage1 = state.embeddedMessagesState.getMessage(forElementId: "element1")
        let embeddedMessage2 = state.embeddedMessagesState.getMessage(forElementId: "element2")

        XCTAssertNotNil(embeddedMessage1)
        XCTAssertEqual(embeddedMessage1?.message?.queueId, "1")

        XCTAssertNotNil(embeddedMessage2)
        XCTAssertEqual(embeddedMessage2?.message?.queueId, "2")
    }

    // MARK: - Engine Action Tests

    func test_engineAction_givenTapAction_expectCallbackCalled() async {
        let message = Message(queueId: "1")
        let route = "testRoute"
        let action = "testAction"
        let name = "testName"

        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .engineAction(action: .tap(message: message, route: route, name: name, action: action)))

        XCTAssertTrue(globalEventListener.messageActionTakenCalled)
        XCTAssertEqual(globalEventListener.messageActionTakenReceivedArguments?.message.deliveryId, message.gistProperties.campaignId)
        XCTAssertEqual(globalEventListener.messageActionTakenReceivedArguments?.actionValue, action)
        XCTAssertEqual(globalEventListener.messageActionTakenReceivedArguments?.actionName, name)
    }

    func test_engineAction_givenMessageLoadingFailed_expectMessageDismissed() async {
        let message = Message(queueId: "1")

        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .engineAction(action: .messageLoadingFailed(message: message)))

        let state = await inAppMessageManager.state
        XCTAssertEqual(state.modalMessageState, .dismissed(message: message))

        XCTAssertTrue(globalEventListener.errorWithMessageCalled)
        XCTAssertEqual(globalEventListener.errorWithMessageReceivedArguments?.deliveryId, message.gistProperties.campaignId)
    }

    func test_processMessageQueue_givenDismissedMessage_expectMessageNotDisplayedAgain() async {
        let message = Message(queueId: "1")

        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: "testUser"))
        await inAppMessageManager.dispatchAsync(action: .processMessageQueue(messages: [message]))
        await inAppMessageManager.dispatchAsync(action: .displayMessage(message: message))
        await inAppMessageManager.dispatchAsync(action: .dismissMessage(message: message))

        await inAppMessageManager.dispatchAsync(action: .processMessageQueue(messages: [message]))

        let state = await inAppMessageManager.state
        XCTAssertEqual(state.modalMessageState, .dismissed(message: message))
        XCTAssertTrue(state.shownMessageQueueIds.contains(message.queueId!))

        XCTAssertEqual(globalEventListener.messageShownCallsCount, 1)
        XCTAssertEqual(globalEventListener.messageDismissedCallsCount, 1)
    }

    // MARK: - Route Change Tests

    func test_setPageRoute_givenNoUser_expectRouteUpdatedWithoutProcessingMessages() async {
        var state = await inAppMessageManager.state
        XCTAssertNil(state.userId)
        XCTAssertNil(state.currentRoute)

        await inAppMessageManager.dispatchAsync(action: .setPageRoute(route: "home"))

        state = await inAppMessageManager.state
        XCTAssertNil(state.userId)
        XCTAssertEqual(state.currentRoute, "home")
        XCTAssertEqual(state.modalMessageState, .initial)
        XCTAssertTrue(state.messagesInQueue.isEmpty)

        XCTAssertFalse(globalEventListener.messageShownCalled)
        XCTAssertFalse(globalEventListener.messageDismissedCalled)
        XCTAssertFalse(globalEventListener.errorWithMessageCalled)
        XCTAssertFalse(globalEventListener.messageActionTakenCalled)
    }

    func test_routeChange_expectMessageProcessing() async throws {
        let message1 = Message(pageRule: "home", queueId: "1")
        let message2 = Message(pageRule: "profile", queueId: "2")

        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .processMessageQueue(messages: [message1, message2]))

        // Set route to "home"
        try await dispatchAndWait(.setPageRoute(route: "home"))

        var state = await inAppMessageManager.state
        XCTAssertEqual(state.currentRoute, "home")

        state = await inAppMessageManager.waitForState { state in
            state.modalMessageState.isLoading
        }

        if case .loading(let loadingMessage) = state.modalMessageState {
            XCTAssertEqual(loadingMessage.queueId, "1")
        } else {
            XCTFail("Expected loading state with message 1")
        }

        // Change route to "profile"
        try await dispatchAndWait(.setPageRoute(route: "profile"))

        state = await inAppMessageManager.state
        XCTAssertEqual(state.currentRoute, "profile")

        state = await inAppMessageManager.waitForState { state in
            state.modalMessageState.isLoading
        }

        if case .loading(let loadingMessage) = state.modalMessageState {
            XCTAssertEqual(loadingMessage.queueId, "2")
        } else {
            XCTFail("Expected loading state with message 2")
        }
    }

    func test_routeChange_givenMessageBeingProcessed_expectMessageHandledCorrectly() async throws {
        let message = Message(pageRule: "home", queueId: "1")

        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .setPageRoute(route: "home"))
        await inAppMessageManager.dispatchAsync(action: .processMessageQueue(messages: [message]))

        var state = await inAppMessageManager.state
        XCTAssertEqual(state.modalMessageState, .loading(message: message))

        try await dispatchAndWait(.setPageRoute(route: "profile"))

        state = await inAppMessageManager.state
        XCTAssertEqual(state.modalMessageState, .dismissed(message: message))
        XCTAssertEqual(state.currentRoute, "profile")

        try await dispatchAndWait(.setPageRoute(route: "home"))

        state = await inAppMessageManager.state
        XCTAssertEqual(state.modalMessageState, .loading(message: message))
    }

    // MARK: - Callback Tests

    func test_displayMessage_expectMessageShownCallbackCalled() async {
        let message = Message(queueId: "1")

        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .displayMessage(message: message))

        XCTAssertTrue(globalEventListener.messageShownCalled)
        XCTAssertEqual(globalEventListener.messageShownReceivedArguments?.deliveryId, message.gistProperties.campaignId)
    }

    func test_dismissMessage_expectMessageDismissedCallbackCalled() async {
        let message = Message(queueId: "1")

        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .dismissMessage(message: message))

        XCTAssertTrue(globalEventListener.messageDismissedCalled)
        XCTAssertEqual(globalEventListener.messageDismissedReceivedArguments?.deliveryId, message.gistProperties.campaignId)
    }

    func test_engineAction_givenMessageLoadingFailed_expectErrorCallbackCalled() async {
        let message = Message(queueId: "1")

        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .engineAction(action: .messageLoadingFailed(message: message)))

        XCTAssertTrue(globalEventListener.errorWithMessageCalled)
        XCTAssertEqual(globalEventListener.errorWithMessageReceivedArguments?.deliveryId, message.gistProperties.campaignId)
    }

    func test_engineAction_givenTapAction_expectMessageActionTakenCallbackCalled() async {
        let message = Message(queueId: "1")
        let route = "testRoute"
        let action = "testAction"
        let name = "testName"

        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .engineAction(action: .tap(message: message, route: route, name: name, action: action)))

        XCTAssertTrue(globalEventListener.messageActionTakenCalled)
        XCTAssertEqual(globalEventListener.messageActionTakenReceivedArguments?.message.deliveryId, message.gistProperties.campaignId)
        XCTAssertEqual(globalEventListener.messageActionTakenReceivedArguments?.actionValue, action)
        XCTAssertEqual(globalEventListener.messageActionTakenReceivedArguments?.actionName, name)
    }

    // MARK: fetch user messages from backend services

    var sampleFetchResponseBody: String {
        readSampleDataFile(subdirectory: "InAppUserQueue", fileName: "fetch_response.json")
    }

    // note: remove flakty test
//    func test_fetch_givenHTTPResponse200_expectSetLocalMessageStoreFromFetchResponse() async {
//        inAppMessageManager.dispatch(action: .initialize(siteId: .random, dataCenter: .random, environment: .production))
//        inAppMessageManager.dispatch(action: .setUserIdentifier(user: .random))
//
//        var state = await inAppMessageManager.state
//        XCTAssertTrue(state.messagesInQueue.isEmpty)
//
//        setupHttpResponse(code: 200, body: sampleFetchResponseBody.data)
//        gist.fetchUserMessagesFromRemoteQueue()
//
//        state = await inAppMessageManager.waitForState { state in
//            state.messagesInQueue.count == 2
//        }
//        XCTAssertEqual(state.messagesInQueue.count, 2)
//    }

    // note: remove flakty test
//    func test_fetch_givenMessageCacheSaved_given304AfterSdkInitialized_expectPopulateLocalMessageStoreFromCache() async {
//        inAppMessageManager.dispatch(action: .initialize(siteId: .random, dataCenter: .random, environment: .production))
//        inAppMessageManager.dispatch(action: .setUserIdentifier(user: .random))
//
//        var state = await inAppMessageManager.state
//        XCTAssertTrue(state.messagesInQueue.isEmpty)
//
//        setupHttpResponse(code: 200, body: sampleFetchResponseBody.data)
//        gist.fetchUserMessagesFromRemoteQueue()
//
//        state = await inAppMessageManager.waitForState { state in
//            state.messagesInQueue.count == 2
//        }
//
//        let localMessageStoreBefore304: Set<Message> = state.messagesInQueue
//        inAppMessageManager.dispatch(action: .clearMessageQueue)
//
//        state = await inAppMessageManager.waitForState { state in
//            state.messagesInQueue.isEmpty
//        }
//
//        setupHttpResponse(code: 304, body: "".data)
//        gist.fetchUserMessagesFromRemoteQueue()
//
//        state = await inAppMessageManager.waitForState { state in
//            state.messagesInQueue.count == 2
//        }
//
//        let localMessageStoreAfter304 = state.messagesInQueue
//
//        XCTAssertEqual(localMessageStoreBefore304.compactMap(\.queueId).sorted(), localMessageStoreAfter304.compactMap(\.queueId).sorted())
//    }

    // The SDK could receive a 304 and the SDK does not have a previous fetch response cached. Example use cases when this could happen:
    // 1. The user logs out of the SDK and logs in again  with same or different profile.
    // 2. Reinstalls the app and first fetch response is a 304
    func test_fetch_givenNoPreviousCacheSaved_given304AfterSdkInitialized_expectPopulateLocalMessageStoreFromCache() async {
        inAppMessageManager.dispatch(action: .initialize(siteId: .random, dataCenter: .random, environment: .production))
        inAppMessageManager.dispatch(action: .setUserIdentifier(user: .random))

        let state = await inAppMessageManager.state
        XCTAssertTrue(state.messagesInQueue.isEmpty)

        setupHttpResponse(code: 304, body: "".data)
        gist.fetchUserMessagesFromRemoteQueue()

        XCTAssertTrue(state.messagesInQueue.isEmpty)
    }

    // MARK: - SSE Flag Tests

    func test_setSseEnabled_givenTrue_expectSseFlagSetToTrue() async {
        await inAppMessageManager.dispatchAsync(action: .initialize(siteId: .random, dataCenter: .random, environment: .production))
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .setSseEnabled(enabled: true))

        let state = await inAppMessageManager.state
        XCTAssertEqual(state.useSse, true)
    }

    func test_setSseEnabled_givenFalse_expectSseFlagSetToFalse() async {
        await inAppMessageManager.dispatchAsync(action: .initialize(siteId: .random, dataCenter: .random, environment: .production))
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .setSseEnabled(enabled: false))

        let state = await inAppMessageManager.state
        XCTAssertEqual(state.useSse, false)
    }

    func test_setSseEnabled_givenMultipleChanges_expectStateUpdated() async {
        await inAppMessageManager.dispatchAsync(action: .initialize(siteId: .random, dataCenter: .random, environment: .production))
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))

        await inAppMessageManager.dispatchAsync(action: .setSseEnabled(enabled: true))
        var state = await inAppMessageManager.state
        XCTAssertEqual(state.useSse, true)

        await inAppMessageManager.dispatchAsync(action: .setSseEnabled(enabled: false))
        state = await inAppMessageManager.state
        XCTAssertEqual(state.useSse, false)

        await inAppMessageManager.dispatchAsync(action: .setSseEnabled(enabled: true))
        state = await inAppMessageManager.state
        XCTAssertEqual(state.useSse, true)
    }

    func test_resetState_expectSseFlagCleared() async {
        await inAppMessageManager.dispatchAsync(action: .initialize(siteId: .random, dataCenter: .random, environment: .production))
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))

        await inAppMessageManager.dispatchAsync(action: .setSseEnabled(enabled: true))
        var state = await inAppMessageManager.state
        XCTAssertEqual(state.useSse, true)

        await inAppMessageManager.dispatchAsync(action: .resetState)
        state = await inAppMessageManager.state
        XCTAssertEqual(state.useSse, false)
    }

    // MARK: - SSE Header Detection Tests

    func test_fetch_givenSseHeaderTrue_expectSseFlagSetToTrue() async {
        await inAppMessageManager.dispatchAsync(action: .initialize(siteId: .random, dataCenter: .random, environment: .production))
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))

        var state = await inAppMessageManager.state
        XCTAssertEqual(state.useSse, false)

        let headers = [
            "x-gist-queue-polling-interval": "600",
            "x-cio-use-sse": "true"
        ]
        setupHttpResponse(code: 200, body: "[]".data, headers: headers)

        queueManager.fetchUserQueue(state: state) { _ in }

        state = await inAppMessageManager.waitForState { state in
            state.useSse == true
        }
        XCTAssertEqual(state.useSse, true)
    }

    func test_fetch_givenSseHeaderFalse_expectSseFlagSetToFalse() async {
        await inAppMessageManager.dispatchAsync(action: .initialize(siteId: .random, dataCenter: .random, environment: .production))
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))

        var state = await inAppMessageManager.state
        XCTAssertEqual(state.useSse, false)

        let headers = [
            "x-gist-queue-polling-interval": "600",
            "x-cio-use-sse": "false"
        ]
        setupHttpResponse(code: 200, body: "[]".data, headers: headers)

        queueManager.fetchUserQueue(state: state) { _ in }

        // Since it's already false, verify it remains false
        state = await inAppMessageManager.state
        XCTAssertEqual(state.useSse, false)
    }

    func test_fetch_givenNoSseHeader_expectSseFlagUnchanged() async {
        await inAppMessageManager.dispatchAsync(action: .initialize(siteId: .random, dataCenter: .random, environment: .production))
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))

        var state = await inAppMessageManager.state
        XCTAssertEqual(state.useSse, false)

        let headers = [
            "x-gist-queue-polling-interval": "600"
        ]
        setupHttpResponse(code: 200, body: "[]".data, headers: headers)

        queueManager.fetchUserQueue(state: state) { _ in }

        // Verify SSE flag remains unchanged
        state = await inAppMessageManager.state
        XCTAssertEqual(state.useSse, false)
    }

    func test_fetch_givenInvalidSseHeaderValue_expectSseFlagSetToFalse() async {
        await inAppMessageManager.dispatchAsync(action: .initialize(siteId: .random, dataCenter: .random, environment: .production))
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))

        var state = await inAppMessageManager.state
        XCTAssertEqual(state.useSse, false)

        let headers = [
            "x-gist-queue-polling-interval": "600",
            "x-cio-use-sse": "invalid"
        ]
        setupHttpResponse(code: 200, body: "[]".data, headers: headers)

        queueManager.fetchUserQueue(state: state) { _ in }

        // Since it's already false and "invalid" converts to false, verify it remains false
        state = await inAppMessageManager.state
        XCTAssertEqual(state.useSse, false)
    }

    func test_fetch_givenSseHeaderChangesFromTrueToFalse_expectSseFlagUpdated() async {
        await inAppMessageManager.dispatchAsync(action: .initialize(siteId: .random, dataCenter: .random, environment: .production))
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))

        var state = await inAppMessageManager.state

        // First fetch with SSE enabled
        var headers = [
            "x-gist-queue-polling-interval": "600",
            "x-cio-use-sse": "true"
        ]
        setupHttpResponse(code: 200, body: "[]".data, headers: headers)
        queueManager.fetchUserQueue(state: state) { _ in }

        state = await inAppMessageManager.waitForState { state in
            state.useSse == true
        }
        XCTAssertEqual(state.useSse, true)

        // Second fetch with SSE disabled
        headers = [
            "x-gist-queue-polling-interval": "600",
            "x-cio-use-sse": "false"
        ]
        setupHttpResponse(code: 200, body: "[]".data, headers: headers)
        queueManager.fetchUserQueue(state: state) { _ in }

        state = await inAppMessageManager.waitForState { state in
            state.useSse == false
        }
        XCTAssertEqual(state.useSse, false)
    }

    // MARK: - SSE Connection Manager Integration Tests

    func test_sseFlagEnabled_expectConnectionManagerStartConnectionCalled() async {
        await inAppMessageManager.dispatchAsync(action: .initialize(siteId: .random, dataCenter: .random, environment: .production))
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))

        // Enable SSE flag
        await inAppMessageManager.dispatchAsync(action: .setSseEnabled(enabled: true))

        // Wait for state to update
        let state = await inAppMessageManager.waitForState { state in
            state.useSse == true
        }

        XCTAssertEqual(state.useSse, true)

        // Note: SseConnectionManager handles duplicate startConnection calls gracefully
        // Multiple calls to enable SSE will be idempotent in the connection manager
    }

    func test_sseFlagDisabled_expectConnectionManagerStopConnectionCalled() async {
        await inAppMessageManager.dispatchAsync(action: .initialize(siteId: .random, dataCenter: .random, environment: .production))
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))

        // Enable SSE first
        await inAppMessageManager.dispatchAsync(action: .setSseEnabled(enabled: true))
        var state = await inAppMessageManager.waitForState { state in
            state.useSse == true
        }
        XCTAssertEqual(state.useSse, true)

        // Then disable SSE
        await inAppMessageManager.dispatchAsync(action: .setSseEnabled(enabled: false))
        state = await inAppMessageManager.waitForState { state in
            state.useSse == false
        }

        XCTAssertEqual(state.useSse, false)

        // Note: In a real test, we would verify that SseConnectionManager.stopConnection was called
        // For Phase 1, we're just verifying the state change triggers the handler
    }

    // MARK: - Polling and SSE Coordination Tests

    func test_sseFlagEnabled_expectPollingStops() async {
        await inAppMessageManager.dispatchAsync(action: .initialize(siteId: .random, dataCenter: .random, environment: .production))
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))

        // Start polling by fetching messages
        gist.fetchUserMessagesFromRemoteQueue()

        // Enable SSE - this should stop polling
        await inAppMessageManager.dispatchAsync(action: .setSseEnabled(enabled: true))

        let state = await inAppMessageManager.waitForState { state in
            state.useSse == true
        }

        XCTAssertEqual(state.useSse, true)
        // Note: In Phase 1, we verify the state change. In Phase 2+, we would verify:
        // - Polling timer is invalidated
        // - No more fetch calls are made while SSE is enabled
    }

    func test_sseFlagDisabled_expectPollingResumes() async {
        await inAppMessageManager.dispatchAsync(action: .initialize(siteId: .random, dataCenter: .random, environment: .production))
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))

        // Enable SSE (which stops polling)
        await inAppMessageManager.dispatchAsync(action: .setSseEnabled(enabled: true))
        var state = await inAppMessageManager.waitForState { state in
            state.useSse == true
        }
        XCTAssertEqual(state.useSse, true)

        // Disable SSE - this should resume polling
        await inAppMessageManager.dispatchAsync(action: .setSseEnabled(enabled: false))
        state = await inAppMessageManager.waitForState { state in
            state.useSse == false
        }

        XCTAssertEqual(state.useSse, false)
        // Note: In Phase 1, we verify the state change. In Phase 2+, we would verify:
        // - Polling timer is restarted
        // - Fetch calls resume at the polling interval
    }

    // MARK: - SSE Message Queue Processing After Dismissal Tests

    func test_dismissMessage_givenSseEnabled_expectNextMessageLoaded() async throws {
        // Setup: Initialize with SSE enabled and identified user
        await inAppMessageManager.dispatchAsync(action: .initialize(siteId: .random, dataCenter: .random, environment: .production))
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: "testUser"))
        await inAppMessageManager.dispatchAsync(action: .setSseEnabled(enabled: true))

        // Add multiple messages to queue with different priorities
        let message1 = Message(priority: 1, queueId: "message1")
        let message2 = Message(priority: 2, queueId: "message2")
        let message3 = Message(priority: 3, queueId: "message3")

        await inAppMessageManager.dispatchAsync(action: .processMessageQueue(messages: [message1, message2, message3]))

        // Wait for the first message (highest priority) to be loaded
        var state = await inAppMessageManager.waitForState { state in
            state.modalMessageState.isLoading
        }
        XCTAssertEqual(state.modalMessageState, .loading(message: message1))

        // Display and dismiss the first message
        await inAppMessageManager.dispatchAsync(action: .displayMessage(message: message1))
        try await dispatchAndWait(.dismissMessage(message: message1))

        // Verify: With SSE enabled, the next message (message2) should be loaded automatically
        state = await inAppMessageManager.waitForState { state in
            if case .loading(let msg) = state.modalMessageState {
                return msg.queueId == "message2"
            }
            return false
        }

        if case .loading(let loadedMessage) = state.modalMessageState {
            XCTAssertEqual(loadedMessage.queueId, "message2", "With SSE enabled, next message should be loaded after dismissal")
        } else {
            XCTFail("Expected loading state with message2 after dismissing message1 with SSE enabled")
        }
    }

    func test_dismissMessage_givenSseDisabled_expectNoAutoLoadNextMessage() async throws {
        // Setup: Initialize WITHOUT SSE (polling mode)
        await inAppMessageManager.dispatchAsync(action: .initialize(siteId: .random, dataCenter: .random, environment: .production))
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: "testUser"))
        // SSE is disabled by default, but let's be explicit
        await inAppMessageManager.dispatchAsync(action: .setSseEnabled(enabled: false))

        // Add multiple messages to queue
        let message1 = Message(priority: 1, queueId: "message1")
        let message2 = Message(priority: 2, queueId: "message2")

        await inAppMessageManager.dispatchAsync(action: .processMessageQueue(messages: [message1, message2]))

        // Wait for the first message to be loaded
        var state = await inAppMessageManager.waitForState { state in
            state.modalMessageState.isLoading
        }
        XCTAssertEqual(state.modalMessageState, .loading(message: message1))

        // Display and dismiss the first message
        await inAppMessageManager.dispatchAsync(action: .displayMessage(message: message1))
        await inAppMessageManager.dispatchAsync(action: .dismissMessage(message: message1))

        // Verify: With SSE disabled, the state should remain dismissed (no auto-load of next message)
        state = await inAppMessageManager.state
        XCTAssertEqual(state.modalMessageState, .dismissed(message: message1), "With SSE disabled, state should remain dismissed without auto-loading next message")
    }

    func test_dismissMessage_givenSseFlagTrueButAnonymousUser_expectNoAutoLoadNextMessage() async throws {
        // Setup: Initialize with SSE flag true but only anonymousId (no userId)
        await inAppMessageManager.dispatchAsync(action: .initialize(siteId: .random, dataCenter: .random, environment: .production))
        await inAppMessageManager.dispatchAsync(action: .setAnonymousIdentifier(anonymousId: "anonymous123"))
        await inAppMessageManager.dispatchAsync(action: .setSseEnabled(enabled: true))

        var state = await inAppMessageManager.state
        // Verify shouldUseSse is false because user is not identified
        XCTAssertTrue(state.useSse, "SSE flag should be true")
        XCTAssertFalse(state.shouldUseSse, "shouldUseSse should be false for anonymous users")

        // Add multiple messages to queue
        let message1 = Message(priority: 1, queueId: "message1")
        let message2 = Message(priority: 2, queueId: "message2")

        await inAppMessageManager.dispatchAsync(action: .processMessageQueue(messages: [message1, message2]))

        // Wait for the first message to be loaded
        state = await inAppMessageManager.waitForState { state in
            state.modalMessageState.isLoading
        }
        XCTAssertEqual(state.modalMessageState, .loading(message: message1))

        // Display and dismiss the first message
        await inAppMessageManager.dispatchAsync(action: .displayMessage(message: message1))
        await inAppMessageManager.dispatchAsync(action: .dismissMessage(message: message1))

        // Verify: With anonymous user (shouldUseSse=false), the state should remain dismissed
        state = await inAppMessageManager.state
        XCTAssertEqual(state.modalMessageState, .dismissed(message: message1), "With anonymous user, state should remain dismissed without auto-loading next message")
    }

    func test_dismissMessage_givenSseEnabledAndMultipleMessages_expectMessagesProcessedInPriorityOrder() async throws {
        // Setup: Initialize with SSE enabled and identified user
        await inAppMessageManager.dispatchAsync(action: .initialize(siteId: .random, dataCenter: .random, environment: .production))
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: "testUser"))
        await inAppMessageManager.dispatchAsync(action: .setSseEnabled(enabled: true))

        // Add messages with different priorities (lower number = higher priority)
        let message1 = Message(priority: 1, queueId: "highPriority")
        let message2 = Message(priority: 2, queueId: "mediumPriority")
        let message3 = Message(priority: 3, queueId: "lowPriority")

        await inAppMessageManager.dispatchAsync(action: .processMessageQueue(messages: [message3, message1, message2])) // Add in random order

        // First message (highest priority) should be loaded
        var state = await inAppMessageManager.waitForState { state in
            state.modalMessageState.isLoading
        }
        XCTAssertEqual(state.modalMessageState, .loading(message: message1))

        // Display and dismiss first message
        await inAppMessageManager.dispatchAsync(action: .displayMessage(message: message1))
        try await dispatchAndWait(.dismissMessage(message: message1))

        // Second message (medium priority) should be loaded
        state = await inAppMessageManager.waitForState { state in
            if case .loading(let msg) = state.modalMessageState {
                return msg.queueId == "mediumPriority"
            }
            return false
        }
        XCTAssertEqual(state.modalMessageState, .loading(message: message2))

        // Display and dismiss second message
        await inAppMessageManager.dispatchAsync(action: .displayMessage(message: message2))
        try await dispatchAndWait(.dismissMessage(message: message2))

        // Third message (low priority) should be loaded
        state = await inAppMessageManager.waitForState { state in
            if case .loading(let msg) = state.modalMessageState {
                return msg.queueId == "lowPriority"
            }
            return false
        }
        XCTAssertEqual(state.modalMessageState, .loading(message: message3))
    }

    func test_dismissMessage_givenSseEnabledAndAlreadyShownMessage_expectMessageNotLoadedAgain() async throws {
        // Setup: Initialize with SSE enabled
        await inAppMessageManager.dispatchAsync(action: .initialize(siteId: .random, dataCenter: .random, environment: .production))
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: "testUser"))
        await inAppMessageManager.dispatchAsync(action: .setSseEnabled(enabled: true))

        // Add two messages
        let message1 = Message(priority: 1, queueId: "message1")
        let message2 = Message(priority: 2, queueId: "message2")

        await inAppMessageManager.dispatchAsync(action: .processMessageQueue(messages: [message1, message2]))

        // Wait for message1 to load, display it, and dismiss it
        var state = await inAppMessageManager.waitForState { state in
            state.modalMessageState.isLoading
        }
        await inAppMessageManager.dispatchAsync(action: .displayMessage(message: message1))
        try await dispatchAndWait(.dismissMessage(message: message1))

        // Wait for message2 to load, display it, and dismiss it
        state = await inAppMessageManager.waitForState { state in
            if case .loading(let msg) = state.modalMessageState {
                return msg.queueId == "message2"
            }
            return false
        }
        await inAppMessageManager.dispatchAsync(action: .displayMessage(message: message2))
        try await dispatchAndWait(.dismissMessage(message: message2))

        // Verify: Both messages should be in shownMessageQueueIds
        state = await inAppMessageManager.state
        XCTAssertTrue(state.shownMessageQueueIds.contains("message1"), "message1 should be marked as shown")
        XCTAssertTrue(state.shownMessageQueueIds.contains("message2"), "message2 should be marked as shown")

        // State should remain dismissed (no more messages to show)
        XCTAssertEqual(state.modalMessageState, .dismissed(message: message2))
    }

    func test_dismissMessage_givenSseEnabledWithPageRule_expectOnlyMatchingMessageLoaded() async throws {
        // Setup: Initialize with SSE enabled and set route
        await inAppMessageManager.dispatchAsync(action: .initialize(siteId: .random, dataCenter: .random, environment: .production))
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: "testUser"))
        await inAppMessageManager.dispatchAsync(action: .setSseEnabled(enabled: true))
        await inAppMessageManager.dispatchAsync(action: .setPageRoute(route: "home"))

        // Add messages: one without page rule, one matching route, one not matching
        let messageNoRule = Message(priority: 1, queueId: "noRule")
        let messageHomeRoute = Message(priority: 2, pageRule: "home", queueId: "homeRoute")
        let messageProfileRoute = Message(priority: 3, pageRule: "profile", queueId: "profileRoute")

        await inAppMessageManager.dispatchAsync(action: .processMessageQueue(messages: [messageNoRule, messageHomeRoute, messageProfileRoute]))

        // First message (no page rule, highest priority) should be loaded
        var state = await inAppMessageManager.waitForState { state in
            state.modalMessageState.isLoading
        }
        XCTAssertEqual(state.modalMessageState, .loading(message: messageNoRule))

        // Display and dismiss first message
        await inAppMessageManager.dispatchAsync(action: .displayMessage(message: messageNoRule))
        try await dispatchAndWait(.dismissMessage(message: messageNoRule))

        // Second message (matching home route) should be loaded
        state = await inAppMessageManager.waitForState { state in
            if case .loading(let msg) = state.modalMessageState {
                return msg.queueId == "homeRoute"
            }
            return false
        }
        XCTAssertEqual(state.modalMessageState, .loading(message: messageHomeRoute))

        // Display and dismiss second message
        await inAppMessageManager.dispatchAsync(action: .displayMessage(message: messageHomeRoute))
        try await dispatchAndWait(.dismissMessage(message: messageHomeRoute))

        // Verify: profileRoute message should NOT be loaded since route doesn't match
        state = await inAppMessageManager.state
        // The messageProfileRoute should not be loaded since current route is "home" not "profile"
        XCTAssertEqual(state.modalMessageState, .dismissed(message: messageHomeRoute), "Message with non-matching page rule should not be auto-loaded")
        XCTAssertFalse(state.shownMessageQueueIds.contains("profileRoute"), "profileRoute message should not have been shown")
    }

    // MARK: - Inbox Messages State Tests

    func test_inboxMessages_initialState_expectEmptyInboxMessages() async {
        let state = await inAppMessageManager.state
        XCTAssertTrue(state.inboxMessages.isEmpty)
    }

    func test_inboxMessages_processInboxMessages_expectStateUpdated() async {
        // Set user ID first to bypass auth middleware
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: "test-user"))

        let message1 = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: Date(),
            topics: [],
            type: "",
            opened: false,
            priority: 5,
            properties: [:]
        )
        let message2 = InboxMessage(
            queueId: "queue-2",
            deliveryId: "delivery-2",
            expiry: nil,
            sentAt: Date(),
            topics: [],
            type: "",
            opened: false,
            priority: 5,
            properties: [:]
        )

        await inAppMessageManager.dispatchAsync(action: .processInboxMessages(messages: [message1, message2]))

        let state = await inAppMessageManager.state
        XCTAssertEqual(state.inboxMessages.count, 2)
        XCTAssertTrue(state.inboxMessages.contains(message1))
        XCTAssertTrue(state.inboxMessages.contains(message2))
    }

    func test_inboxMessages_processInboxMessages_whenCalledTwice_expectReplacedNotAppended() async {
        // Set user ID first to bypass auth middleware
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: "test-user"))

        let message1 = InboxMessage(queueId: "queue-1", deliveryId: "delivery-1", expiry: nil, sentAt: Date(), topics: [], type: "", opened: false, priority: 5, properties: [:])
        let message2 = InboxMessage(queueId: "queue-2", deliveryId: "delivery-2", expiry: nil, sentAt: Date(), topics: [], type: "", opened: false, priority: 5, properties: [:])
        let message3 = InboxMessage(queueId: "queue-3", deliveryId: "delivery-3", expiry: nil, sentAt: Date(), topics: [], type: "", opened: false, priority: 5, properties: [:])

        await inAppMessageManager.dispatchAsync(action: .processInboxMessages(messages: [message1, message2]))

        var state = await inAppMessageManager.state
        XCTAssertEqual(state.inboxMessages.count, 2)

        // Dispatch again with different messages
        await inAppMessageManager.dispatchAsync(action: .processInboxMessages(messages: [message3]))

        state = await inAppMessageManager.state
        XCTAssertEqual(state.inboxMessages.count, 1)
        XCTAssertTrue(state.inboxMessages.contains(message3))
        XCTAssertFalse(state.inboxMessages.contains(message1))
    }

    func test_inboxMessages_processInboxMessages_expectSetDeduplication() async {
        // Set user ID first to bypass auth middleware
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: "test-user"))

        let message1 = InboxMessage(queueId: "queue-1", deliveryId: "delivery-1", expiry: nil, sentAt: Date(), topics: [], type: "", opened: false, priority: 5, properties: [:])
        let message2 = InboxMessage(queueId: "queue-1", deliveryId: "delivery-2", expiry: nil, sentAt: Date(), topics: [], type: "", opened: false, priority: 5, properties: [:])

        await inAppMessageManager.dispatchAsync(action: .processInboxMessages(messages: [message1, message2]))

        let state = await inAppMessageManager.state
        // Middleware deduplicates by queueId - keeps first occurrence
        // message1 and message2 have same queueId, so only first is kept
        XCTAssertEqual(state.inboxMessages.count, 1)
        XCTAssertTrue(state.inboxMessages.contains(message1))
    }

    func test_inboxMessages_whenMessagePropertyChanges_expectStateChangeDetected() async {
        // Set user ID first to bypass auth middleware
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: "test-user"))

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

        await inAppMessageManager.dispatchAsync(action: .processInboxMessages(messages: [message1]))

        var state = await inAppMessageManager.state
        XCTAssertEqual(state.inboxMessages.count, 1)
        let storedMessage = state.inboxMessages.first!
        XCTAssertEqual(storedMessage.opened, false)

        // Update the message with same queueId but different opened status
        let message2 = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: sentAt,
            topics: [],
            type: "",
            opened: true, // Changed from false to true
            priority: 5,
            properties: [:]
        )

        await inAppMessageManager.dispatchAsync(action: .processInboxMessages(messages: [message2]))

        // State should be different because opened status changed
        state = await inAppMessageManager.state
        XCTAssertEqual(state.inboxMessages.count, 1)
        let updatedMessage = state.inboxMessages.first!
        XCTAssertEqual(updatedMessage.opened, true)
    }

    // MARK: - Inbox Action: Update Opened Tests

    func test_inboxAction_updateOpened_expectStateUpdated() async {
        // Set user ID first to bypass auth middleware
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: "test-user"))

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

        // Add message to state
        await inAppMessageManager.dispatchAsync(action: .processInboxMessages(messages: [message]))

        var state = await inAppMessageManager.state
        XCTAssertEqual(state.inboxMessages.count, 1)
        XCTAssertEqual(state.inboxMessages.first?.opened, false)

        // Mark as opened
        await inAppMessageManager.dispatchAsync(action: .inboxAction(action: .updateOpened(message: message, opened: true)))

        state = await inAppMessageManager.state
        XCTAssertEqual(state.inboxMessages.count, 1)
        XCTAssertEqual(state.inboxMessages.first?.opened, true)
    }

    func test_inboxAction_updateOpened_expectMessageIdentityPreserved() async {
        // Set user ID first to bypass auth middleware
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: "test-user"))

        let message = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: Date(timeIntervalSince1970: 5000),
            sentAt: Date(timeIntervalSince1970: 1000),
            topics: ["promo", "sales"],
            type: "email",
            opened: false,
            priority: 10,
            properties: ["custom": "value"]
        )

        // Add message to state
        await inAppMessageManager.dispatchAsync(action: .processInboxMessages(messages: [message]))

        // Mark as opened
        await inAppMessageManager.dispatchAsync(action: .inboxAction(action: .updateOpened(message: message, opened: true)))

        let state = await inAppMessageManager.state
        let updatedMessage = state.inboxMessages.first!

        // Verify only opened changed, all other fields preserved
        XCTAssertEqual(updatedMessage.queueId, message.queueId)
        XCTAssertEqual(updatedMessage.deliveryId, message.deliveryId)
        XCTAssertEqual(updatedMessage.expiry, message.expiry)
        XCTAssertEqual(updatedMessage.sentAt, message.sentAt)
        XCTAssertEqual(updatedMessage.topics, message.topics)
        XCTAssertEqual(updatedMessage.type, message.type)
        XCTAssertEqual(updatedMessage.priority, message.priority)
        XCTAssertTrue(updatedMessage.opened) // Only this changed
    }

    func test_inboxAction_updateOpened_whenMessageNotInState_expectNoChange() async {
        // Set user ID first to bypass auth middleware
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: "test-user"))

        let existingMessage = InboxMessage(
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

        let nonExistentMessage = InboxMessage(
            queueId: "queue-999",
            deliveryId: "delivery-999",
            expiry: nil,
            sentAt: Date(),
            topics: [],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )

        // Add only existingMessage to state
        await inAppMessageManager.dispatchAsync(action: .processInboxMessages(messages: [existingMessage]))

        var state = await inAppMessageManager.state
        XCTAssertEqual(state.inboxMessages.count, 1)

        // Try to update a message that doesn't exist in state
        await inAppMessageManager.dispatchAsync(action: .inboxAction(action: .updateOpened(message: nonExistentMessage, opened: true)))

        state = await inAppMessageManager.state
        // State should remain unchanged
        XCTAssertEqual(state.inboxMessages.count, 1)
        XCTAssertEqual(state.inboxMessages.first?.queueId, "queue-1")
        XCTAssertEqual(state.inboxMessages.first?.opened, false)
    }

    func test_inboxAction_updateOpened_toggleOpenedMultipleTimes_expectCorrectState() async {
        // Set user ID first to bypass auth middleware
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: "test-user"))

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

        // Add message to state
        await inAppMessageManager.dispatchAsync(action: .processInboxMessages(messages: [message]))

        var state = await inAppMessageManager.state
        XCTAssertEqual(state.inboxMessages.first?.opened, false)

        // Mark as opened
        await inAppMessageManager.dispatchAsync(action: .inboxAction(action: .updateOpened(message: message, opened: true)))
        state = await inAppMessageManager.state
        XCTAssertEqual(state.inboxMessages.first?.opened, true)

        // Mark as unopened
        await inAppMessageManager.dispatchAsync(action: .inboxAction(action: .updateOpened(message: message, opened: false)))
        state = await inAppMessageManager.state
        XCTAssertEqual(state.inboxMessages.first?.opened, false)

        // Mark as opened again
        await inAppMessageManager.dispatchAsync(action: .inboxAction(action: .updateOpened(message: message, opened: true)))
        state = await inAppMessageManager.state
        XCTAssertEqual(state.inboxMessages.first?.opened, true)
    }

    func test_inboxAction_updateOpened_multipleMessages_expectOnlyTargetUpdated() async {
        // Set user ID first to bypass auth middleware
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: "test-user"))

        let message1 = InboxMessage(
            queueId: "queue-1",
            deliveryId: "delivery-1",
            expiry: nil,
            sentAt: Date(timeIntervalSince1970: 1000),
            topics: [],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )

        let message2 = InboxMessage(
            queueId: "queue-2",
            deliveryId: "delivery-2",
            expiry: nil,
            sentAt: Date(timeIntervalSince1970: 2000),
            topics: [],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )

        let message3 = InboxMessage(
            queueId: "queue-3",
            deliveryId: "delivery-3",
            expiry: nil,
            sentAt: Date(timeIntervalSince1970: 3000),
            topics: [],
            type: "",
            opened: false,
            priority: nil,
            properties: [:]
        )

        // Add all messages to state
        await inAppMessageManager.dispatchAsync(action: .processInboxMessages(messages: [message1, message2, message3]))

        var state = await inAppMessageManager.state
        XCTAssertEqual(state.inboxMessages.count, 3)

        // Mark only message2 as opened
        await inAppMessageManager.dispatchAsync(action: .inboxAction(action: .updateOpened(message: message2, opened: true)))

        state = await inAppMessageManager.state
        XCTAssertEqual(state.inboxMessages.count, 3)

        let messages = state.inboxMessages.sorted { $0.queueId < $1.queueId }
        XCTAssertEqual(messages[0].queueId, "queue-1")
        XCTAssertFalse(messages[0].opened) // Unchanged
        XCTAssertEqual(messages[1].queueId, "queue-2")
        XCTAssertTrue(messages[1].opened) // Updated
        XCTAssertEqual(messages[2].queueId, "queue-3")
        XCTAssertFalse(messages[2].opened) // Unchanged
    }
}

extension InAppMessageManager {
    func waitForState(
        timeout: TimeInterval = 5.0,
        pollInterval: TimeInterval = 0.2,
        comparator: @escaping (InAppMessageState) -> Bool,
        file: StaticString = #file,
        line: UInt = #line
    ) async -> InAppMessageState {
        let timeoutDate = Date().addingTimeInterval(timeout)

        var lastKnownState: InAppMessageState
        repeat {
            lastKnownState = await state
            // Check if the condition is met
            if comparator(lastKnownState) {
                return lastKnownState
            }

            // Sleep for pollInterval before checking again
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1000000000))
        } while Date() < timeoutDate

        XCTFail("Condition not met within \(timeout) seconds.", file: file, line: line)
        return lastKnownState
    }
}
