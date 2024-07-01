@testable import CioMessagingInApp
import Foundation
import SharedTests
import XCTest

class MessagingInAppIntegrationTest: IntegrationTest {
    private let globalEventListener = InAppEventListenerMock()

    private var messageQueueManager: MessageQueueManagerImpl {
        // swiftlint:disable:next force_cast
        Gist.shared.messageQueueManager as! MessageQueueManagerImpl
    }

    override func setUp() {
        super.setUp()

        // Important to test if global event listener gets called. Register one to test.
        MessagingInApp.shared.setEventListener(globalEventListener)
    }

    // MARK: Page rules and modal messages

    // When a customer adds page rules to a message, they expect that message to only be shown on that screen.

    @MainActor
    func test_givenUserNavigatedToDifferentScreenWhileMessageLoading_expectDoNotShowModalMessage() async {
        navigateToScreen(screenName: "Home")

        let givenMessages = [
            Message(messageId: "welcome-banner", campaignId: .random, pageRule: "^(Home)$")
        ]

        onDoneFetching(messages: givenMessages)
        XCTAssertTrue(isCurrentlyLoadingMessage)

        navigateToScreen(screenName: "Settings")
        XCTAssertFalse(isCurrentlyLoadingMessage)

        await onDoneRenderingInAppMessageOnModal(givenMessages[0])

        XCTAssertNil(currentlyShownModalMessage)
        XCTAssertFalse(didCallGlobalEventListener)
    }

    @MainActor
    func test_givenUserStillOnSameScreenAfterMessageLoads_expectShowModalMessage() async {
        navigateToScreen(screenName: "Home")

        let givenMessages = [
            Message(messageId: "welcome-banner", campaignId: .random, pageRule: "^(Home)$")
        ]
        onDoneFetching(messages: givenMessages)
        XCTAssertTrue(isCurrentlyLoadingMessage)

        await onDoneRenderingInAppMessageOnModal(givenMessages[0])

        XCTAssertNotNil(currentlyShownModalMessage)
        XCTAssertFalse(didCallGlobalEventListener)
    }

    @MainActor
    func test_givenMessageHasNoPageRules_givenUserNavigatedToDifferentScreenWhileMessageLoaded_expectShowModalMessage() async {
        navigateToScreen(screenName: "Home")

        let givenMessages = [
            Message(pageRule: nil)
        ]
        onDoneFetching(messages: givenMessages)
        XCTAssertTrue(isCurrentlyLoadingMessage)

        navigateToScreen(screenName: "Settings")
        XCTAssertTrue(isCurrentlyLoadingMessage)

        await onDoneRenderingInAppMessageOnModal(givenMessages[0])

        XCTAssertEqual(currentlyShownModalMessage, givenMessages[0])
        XCTAssertFalse(didCallGlobalEventListener)
    }

    @MainActor
    func test_givenUserOnScreenDuringFetch_givenUserNavigatedToDifferentScreenWhileMessageLoading_expectShowModalMessageAfterGoBack() async {
        navigateToScreen(screenName: "Home")

        let givenMessages = [
            Message(messageId: "welcome-banner", campaignId: .random, pageRule: "^(Home)$")
        ]
        onDoneFetching(messages: givenMessages)
        XCTAssertTrue(isCurrentlyLoadingMessage)

        navigateToScreen(screenName: "Settings")
        XCTAssertFalse(isCurrentlyLoadingMessage)

        navigateToScreen(screenName: "Home")
        XCTAssertTrue(isCurrentlyLoadingMessage)

        await onDoneRenderingInAppMessageOnModal(givenMessages[0])

        XCTAssertNotNil(currentlyShownModalMessage)
        XCTAssertFalse(didCallGlobalEventListener)
    }

    @MainActor
    func test_givenRouteChangedToSameRoute_expectDoNotDismissModal() async {
        navigateToScreen(screenName: "Home")

        let givenMessages = [
            Message(messageId: "welcome-banner", campaignId: .random, pageRule: "^(Home)$")
        ]
        onDoneFetching(messages: givenMessages)

        await onDoneRenderingInAppMessageOnModal(givenMessages[0])

        XCTAssertNotNil(currentlyShownModalMessage)

        navigateToScreen(screenName: "Home")

        XCTAssertNotNil(currentlyShownModalMessage)
        XCTAssertFalse(didCallGlobalEventListener)
    }

    // page routes can contain regex which could make the message match the next screen navigated to.
    @MainActor
    func test_givenChangedRouteButMessageStillMatchesNewRoute_expectDoNotDismissModal() async {
        navigateToScreen(screenName: "Home")

        let givenMessages = [
            Message(messageId: "welcome-banner", campaignId: .random, pageRule: "^(.*Home.*)$")
        ]
        onDoneFetching(messages: givenMessages)

        await onDoneRenderingInAppMessageOnModal(givenMessages[0])

        XCTAssertNotNil(currentlyShownModalMessage)

        let messageShownBeforeNavigate = currentlyShownModalMessage

        navigateToScreen(screenName: "HomeSettings")

        XCTAssertNotNil(currentlyShownModalMessage)

        // because the message is identical, it was not canceled when the page route changed.
        XCTAssertEqual(messageShownBeforeNavigate?.instanceId, currentlyShownModalMessage?.instanceId)
    }

    // MARK: clearUserToken

    // Code that runs when the profile is logged out of the SDK

    @MainActor
    func test_clearUserToken_givenModalMessageShown_givenModalHasPageRuleSet_expectDismissModal() async {
        navigateToScreen(screenName: "Home")

        let givenMessages = [
            Message(messageId: "welcome-banner", campaignId: .random, pageRule: "^(Home)$")
        ]
        onDoneFetching(messages: givenMessages)
        await onDoneRenderingInAppMessageOnModal(givenMessages[0])
        XCTAssertNotNil(currentlyShownModalMessage)

        Gist.shared.clearUserToken()

        XCTAssertNil(currentlyShownModalMessage)
    }

    @MainActor
    func test_clearUserToken_givenModalMessageShown_givenModalHasNoPageRuleSet_expectDoNotDismissModal() async {
        navigateToScreen(screenName: "Home")

        let givenMessages = [
            Message(messageId: "welcome-banner", campaignId: .random, pageRule: nil)
        ]
        onDoneFetching(messages: givenMessages)
        await onDoneRenderingInAppMessageOnModal(givenMessages[0])
        XCTAssertNotNil(currentlyShownModalMessage)

        Gist.shared.clearUserToken()

        XCTAssertNotNil(currentlyShownModalMessage)
    }

    // The in-app SDK maintains a cache of messages that are returned from the backend. When a profile is logged out of the SDK, we expect the message cache is cleared otherwise we run the risk of displaying messages meant for profile A to profile B.
    @MainActor
    func test_clearUserToken_givenProfileLoggedOutAndNewProfileLoggedIn_expectLocalMessageCacheCleared() {
        Gist.shared.setUserToken("profile-A")

        XCTAssertTrue(messageQueueManager.localMessageStore.isEmpty)
        setupHttpResponse(code: 200, body: readSampleDataFile(subdirectory: "InAppUserQueue", fileName: "fetch_response.json").data)
        messageQueueManager.fetchUserMessages()
        XCTAssertFalse(messageQueueManager.localMessageStore.isEmpty)

        // Expect no messages immediately after logging into another profile.
        Gist.shared.clearUserToken()
        XCTAssertTrue(messageQueueManager.localMessageStore.isEmpty)
        Gist.shared.setUserToken("profile-B")
        XCTAssertTrue(messageQueueManager.localMessageStore.isEmpty)

        // Expect that after first fetch with new profile logged in, the message cache remains empty.
        setupHttpResponse(code: 304, body: "".data)
        messageQueueManager.fetchUserMessages()
        XCTAssertTrue(messageQueueManager.localMessageStore.isEmpty)
    }

    // MARK: action buttons

    @MainActor
    func test_onCloseButton_expectShowNextMessageInQueue() async throws {
        // The test fails because it expects synchronous code, but there is async code. Another PR (https://github.com/customerio/customerio-ios/pull/738) makes tests synchronous. Once merged, we can remove this skip.")
        try skipRunningTest()

        navigateToScreen(screenName: "Home")

        let givenMessages = [
            Message(pageRule: "^(Home)$"),
            Message(pageRule: "^(Home)$"),
            Message(pageRule: nil)
        ]

        onDoneFetching(messages: givenMessages)
        await onDoneRenderingInAppMessageOnModal(givenMessages[0])
        XCTAssertEqual(currentlyShownModalMessage, givenMessages[0])

        await onCloseActionButtonPressedOnModal()

        await onDoneRenderingInAppMessageOnModal(givenMessages[1])

        XCTAssertEqual(currentlyShownModalMessage, givenMessages[1])

        await onCloseActionButtonPressedOnModal()

        await onDoneRenderingInAppMessageOnModal(givenMessages[2])

        XCTAssertEqual(currentlyShownModalMessage, givenMessages[2])

        await onCloseActionButtonPressedOnModal()

        XCTAssertNil(currentlyShownModalMessage)
    }

    @MainActor
    func test_onCloseButton_givenNextMessageDoesNotMatchPageRule_expectDoNotShowNextMessageInQueue() async throws {
        // The test fails because it expects synchronous code, but there is async code. Another PR (https://github.com/customerio/customerio-ios/pull/738) makes tests synchronous. Once merged, we can remove this skip.")
        try skipRunningTest()

        navigateToScreen(screenName: "Home")

        let givenMessages = [
            Message(pageRule: "^(Home)$"),
            Message(pageRule: "^(Settings)$") // expect to not show this message on close.
        ]

        onDoneFetching(messages: givenMessages)
        await onDoneRenderingInAppMessageOnModal(givenMessages[0])
        XCTAssertEqual(currentlyShownModalMessage, givenMessages[0])

        await onCloseActionButtonPressedOnModal()

        XCTAssertFalse(isCurrentlyLoadingMessage) // expect to not being loading a new message.

        navigateToScreen(screenName: "Settings")

        XCTAssertTrue(isCurrentlyLoadingMessage) // When page rule matches, we expect to load new message.
    }
}

extension MessagingInAppIntegrationTest {
    var isCurrentlyLoadingMessage: Bool {
        guard let messageManager = Gist.shared.getModalMessageManager() else {
            return false // no modal message shown or loading
        }
        if messageManager.isShowingMessage {
            return false // message already loaded. We want messages that are still loading.
        }

        return true
    }

    var currentlyShownModalMessage: Message? {
        guard let messageManager = Gist.shared.getModalMessageManager() else {
            return nil // no modal message shown or loading
        }
        if !messageManager.isShowingMessage {
            return nil // message not loaded yet.
        }

        return messageManager.currentMessage
    }

    var didCallGlobalEventListener: Bool {
        globalEventListener.messageDismissedCallsCount > 0
    }

    func onDoneFetching(messages: [Message]) {
        // swiftlint:disable:next force_cast
        (Gist.shared.messageQueueManager as! MessageQueueManagerImpl).processFetchedMessages(messages)
    }

    func navigateToScreen(screenName: String) {
        Gist.shared.setCurrentRoute(screenName)
    }
}
