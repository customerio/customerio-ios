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

        diGraphShared.override(value: CioThreadUtil(), forType: ThreadUtil.self)
        diGraphShared.override(value: engineWebProvider, forType: EngineWebProvider.self)

        inAppMessageManager = InAppMessageStoreManager(
            logger: diGraphShared.logger,
            threadUtil: diGraphShared.threadUtil,
            logManager: diGraphShared.logManager,
            gistDelegate: diGraphShared.gistDelegate
        )

        diGraphShared.override(value: inAppMessageManager, forType: InAppMessageManager.self)

        queueManager = QueueManager(
            keyValueStore: diGraphShared.sharedKeyValueStorage,
            gistQueueNetwork: gistQueueNetworkMock,
            inAppMessageManager: inAppMessageManager,
            logger: diGraphShared.logger
        )

        gist = Gist(
            logger: diGraphShared.logger,
            gistDelegate: diGraphShared.gistDelegate,
            inAppMessageManager: inAppMessageManager,
            queueManager: queueManager,
            threadUtil: diGraphShared.threadUtil
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
        XCTAssertEqual(state.currentMessageState, .initial)
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
        XCTAssertEqual(state.currentMessageState, .displayed(message: message))
        XCTAssertTrue(state.shownMessageQueueIds.contains("1"))
    }

    func test_dismissMessage_expectMessageStateDismissed() async {
        let message = Message(queueId: "1")

        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .dismissMessage(message: message))

        let state = await inAppMessageManager.state
        XCTAssertEqual(state.currentMessageState, .dismissed(message: message))
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
        XCTAssertEqual(state.currentMessageState, .initial)
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
            state.currentMessageState.isLoading
        }

        if case .loading(let message) = state.currentMessageState {
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

        if case .loading(let loadingMessage) = state.currentMessageState {
            XCTAssertEqual(loadingMessage.queueId, "1")
        } else {
            XCTFail("Expected loading state with message")
        }

        // Change route to dismiss the message
        try await dispatchAndWait(.setPageRoute(route: "profile"))

        state = await inAppMessageManager.state
        XCTAssertEqual(state.currentRoute, "profile")

        if case .dismissed(let dismissedMessage) = state.currentMessageState {
            XCTAssertEqual(dismissedMessage.queueId, "1")
        } else {
            XCTFail("Expected dismissed state")
        }
    }

    func test_embedMessage_expectNoStateChange() async {
        let message = Message(queueId: "1")
        let elementId = "testElementId"

        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))
        await inAppMessageManager.dispatchAsync(action: .embedMessage(message: message, elementId: elementId))

        let state = await inAppMessageManager.state
        XCTAssertEqual(state.currentMessageState, .initial)
        XCTAssertFalse(state.shownMessageQueueIds.contains("1"))
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
        XCTAssertEqual(state.currentMessageState, .dismissed(message: message))

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
        XCTAssertEqual(state.currentMessageState, .dismissed(message: message))
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
        XCTAssertEqual(state.currentMessageState, .initial)
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
            state.currentMessageState.isLoading
        }

        if case .loading(let loadingMessage) = state.currentMessageState {
            XCTAssertEqual(loadingMessage.queueId, "1")
        } else {
            XCTFail("Expected loading state with message 1")
        }

        // Change route to "profile"
        try await dispatchAndWait(.setPageRoute(route: "profile"))

        state = await inAppMessageManager.state
        XCTAssertEqual(state.currentRoute, "profile")

        state = await inAppMessageManager.waitForState { state in
            state.currentMessageState.isLoading
        }

        if case .loading(let loadingMessage) = state.currentMessageState {
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
        XCTAssertEqual(state.currentMessageState, .loading(message: message))

        try await dispatchAndWait(.setPageRoute(route: "profile"))

        state = await inAppMessageManager.state
        XCTAssertEqual(state.currentMessageState, .dismissed(message: message))
        XCTAssertEqual(state.currentRoute, "profile")

        try await dispatchAndWait(.setPageRoute(route: "home"))

        state = await inAppMessageManager.state
        XCTAssertEqual(state.currentMessageState, .loading(message: message))
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

    func test_fetch_givenHTTPResponse200_expectSetLocalMessageStoreFromFetchResponse() async {
        inAppMessageManager.dispatch(action: .initialize(siteId: .random, dataCenter: .random, environment: .production))
        inAppMessageManager.dispatch(action: .setUserIdentifier(user: .random))

        var state = await inAppMessageManager.state
        XCTAssertTrue(state.messagesInQueue.isEmpty)

        setupHttpResponse(code: 200, body: sampleFetchResponseBody.data)
        gist.fetchUserMessagesFromRemoteQueue()

        state = await inAppMessageManager.waitForState { state in
            state.messagesInQueue.count == 2
        }
        XCTAssertEqual(state.messagesInQueue.count, 2)
    }

    func test_fetch_givenMessageCacheSaved_given304AfterSdkInitialized_expectPopulateLocalMessageStoreFromCache() async {
        inAppMessageManager.dispatch(action: .initialize(siteId: .random, dataCenter: .random, environment: .production))
        inAppMessageManager.dispatch(action: .setUserIdentifier(user: .random))

        var state = await inAppMessageManager.state
        XCTAssertTrue(state.messagesInQueue.isEmpty)

        setupHttpResponse(code: 200, body: sampleFetchResponseBody.data)
        gist.fetchUserMessagesFromRemoteQueue()

        state = await inAppMessageManager.waitForState { state in
            state.messagesInQueue.count == 2
        }

        let localMessageStoreBefore304: Set<Message> = state.messagesInQueue
        inAppMessageManager.dispatch(action: .clearMessageQueue)

        state = await inAppMessageManager.waitForState { state in
            state.messagesInQueue.isEmpty
        }

        setupHttpResponse(code: 304, body: "".data)
        gist.fetchUserMessagesFromRemoteQueue()

        state = await inAppMessageManager.waitForState { state in
            state.messagesInQueue.count == 2
        }

        let localMessageStoreAfter304 = state.messagesInQueue

        XCTAssertEqual(localMessageStoreBefore304.compactMap(\.queueId).sorted(), localMessageStoreAfter304.compactMap(\.queueId).sorted())
    }

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
