@testable import CioMessagingInApp
import Foundation
import SharedTests
import XCTest

class MessagingInAppIntegrationTest: IntegrationTest {
    private var engineWebProvider: EngineWebProvider {
        EngineWebProviderStub(engineWebMock: engineWebMock)
    }

    private let engineWebMock = EngineWebInstanceMock()

    private let globalEventListener = InAppEventListenerMock()

    override func setUp() {
        super.setUp()

        // Setup mocks to return a non-empty value
        engineWebMock.underlyingView = UIView()

        diGraphShared.override(value: engineWebProvider, forType: EngineWebProvider.self)

        // Important to test if global event listener gets called. Register one to test.
        MessagingInApp.shared.setEventListener(globalEventListener)
    }

    // MARK: Page rules and modal messages

    // When a customer adds page rules to a message, they expect that message to only be shown on that screen.

    func test_givenUserNavigatedToDifferentScreenWhileMessageLoading_expectDoNotShowModalMessage() {
        navigateToScreen(screenName: "Home")

        let givenMessages = [
            Message(messageId: "welcome-banner", campaignId: .random, pageRule: "^(Home)$")
        ]

        onDoneFetching(messages: givenMessages)
        XCTAssertTrue(isCurrentlyLoadingMessage)

        navigateToScreen(screenName: "Settings")
        XCTAssertFalse(isCurrentlyLoadingMessage)

        doneLoadingMessage(givenMessages[0])

        XCTAssertNil(currentlyShownModalMessage)
        XCTAssertFalse(didCallGlobalEventListener)
    }

    func test_givenNavigateToDifferentScreenWhileMessageAnimatingIntoView_expectDoNotShowModalMessage() {
        navigateToScreen(screenName: "Home")

        let givenMessages = [
            Message(messageId: "welcome-banner", campaignId: .random, pageRule: "^(Home)$")
        ]

        let expectToBeginAnimation = expectation(description: "Begin animation")
        viewAnimationRunnerStub.animateClosure = { _ in
            expectToBeginAnimation.fulfill()
            // do not call completion handler to not finish the animation.
        }

        onDoneFetching(messages: givenMessages)
        doneLoadingMessage(givenMessages[0])
        waitForExpectations() // asseret that the animation has begun before we move screens

        navigateToScreen(screenName: "Settings") // during animation, we navigate to another screen.

        XCTAssertFalse(isCurrentlyLoadingMessage)
        XCTAssertNil(currentlyShownModalMessage)
        XCTAssertFalse(didCallGlobalEventListener)
    }

    func test_givenNavigateToDifferentScreenAfterMessageDisplayed_expectDoNotShowModalMessage() {
        navigateToScreen(screenName: "Home")

        let givenMessages = [
            Message(messageId: "welcome-banner", campaignId: .random, pageRule: "^(Home)$")
        ]

        onDoneFetching(messages: givenMessages)
        doneLoadingMessage(givenMessages[0])
        XCTAssertEqual(currentlyShownModalMessage, givenMessages[0])

        navigateToScreen(screenName: "Settings")

        XCTAssertFalse(isCurrentlyLoadingMessage)
        XCTAssertNil(currentlyShownModalMessage)
        XCTAssertFalse(didCallGlobalEventListener)
    }

    func test_givenUserStillOnSameScreenAfterMessageLoads_expectShowModalMessage() {
        navigateToScreen(screenName: "Home")

        let givenMessages = [
            Message(messageId: "welcome-banner", campaignId: .random, pageRule: "^(Home)$")
        ]
        onDoneFetching(messages: givenMessages)
        XCTAssertTrue(isCurrentlyLoadingMessage)

        doneLoadingMessage(givenMessages[0])

        XCTAssertNotNil(currentlyShownModalMessage)
        XCTAssertFalse(didCallGlobalEventListener)
    }

    func test_givenMessageHasNoPageRules_givenUserNavigatedToDifferentScreenWhileMessageLoaded_expectShowModalMessage() {
        navigateToScreen(screenName: "Home")

        let givenMessages = [
            Message(pageRule: nil)
        ]
        onDoneFetching(messages: givenMessages)
        XCTAssertTrue(isCurrentlyLoadingMessage)

        navigateToScreen(screenName: "Settings")
        XCTAssertTrue(isCurrentlyLoadingMessage)

        doneLoadingMessage(givenMessages[0])

        XCTAssertEqual(currentlyShownModalMessage?.queueId, givenMessages[0].queueId)
        XCTAssertFalse(didCallGlobalEventListener)
    }

    func test_givenUserOnScreenDuringFetch_givenUserNavigatedToDifferentScreenWhileMessageLoading_expectShowModalMessageAfterGoBack() {
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

        doneLoadingMessage(givenMessages[0])

        XCTAssertNotNil(currentlyShownModalMessage)
        XCTAssertFalse(didCallGlobalEventListener)
    }

    func test_givenRouteChangedToSameRoute_expectDoNotDismissModal() {
        navigateToScreen(screenName: "Home")

        let givenMessages = [
            Message(messageId: "welcome-banner", campaignId: .random, pageRule: "^(Home)$")
        ]
        onDoneFetching(messages: givenMessages)

        doneLoadingMessage(givenMessages[0])

        XCTAssertNotNil(currentlyShownModalMessage)

        navigateToScreen(screenName: "Home")

        XCTAssertNotNil(currentlyShownModalMessage)
        XCTAssertFalse(didCallGlobalEventListener)
    }

    // page routes can contain regex which could make the message match the next screen navigated to.
    func test_givenChangedRouteButMessageStillMatchesNewRoute_expectDoNotDismissModal() {
        navigateToScreen(screenName: "Home")

        let givenMessages = [
            Message(messageId: "welcome-banner", campaignId: .random, pageRule: "^(.*Home.*)$")
        ]
        onDoneFetching(messages: givenMessages)

        doneLoadingMessage(givenMessages[0])

        XCTAssertNotNil(currentlyShownModalMessage)

        let messageShownBeforeNavigate = currentlyShownModalMessage

        navigateToScreen(screenName: "HomeSettings")

        XCTAssertNotNil(currentlyShownModalMessage)

        // because the message is identical, it was not canceled when the page route changed.
        XCTAssertEqual(messageShownBeforeNavigate?.instanceId, currentlyShownModalMessage?.instanceId)
    }

    // We need to verify, if we change route before rendering is done, what message is being displayed then according to page rule?
    func test_givenMultipleMessagesSentToDevice_givenNavigateToDifferentScreen_expectToDisplayMessageForChangedScreen() {
        navigateToScreen(screenName: "Home")

        let givenMessages = [
            Message(messageId: "welcome-banner", campaignId: .random, pageRule: "Home"),
            Message(messageId: "welcome-banner", campaignId: .random, pageRule: "Settings")
        ]
        onDoneFetching(messages: givenMessages)

        navigateToScreen(screenName: "Settings")

        // Let's say that the Home screen message finished rendering after we navigate to another screen.
        // When we navigate to the Settings screen, both messages finish rendering after a few seconds on the Settings screen.
        doneLoadingMessage(givenMessages[0])
        doneLoadingMessage(givenMessages[1])

        XCTAssertEqual(currentlyShownModalMessage?.gistProperties.routeRule, "Settings")
    }

    func test_givenMultipleMessagesSentToDevice_givenMessagesWithSamePageRule_givenNavigateToDifferentScreen_expectToNotDisplayMessageOnDifferentPage() {
        navigateToScreen(screenName: "Home")

        let givenMessages = [
            Message(messageId: "welcome-banner", campaignId: .random, pageRule: "Home"),
            Message(messageId: "welcome-banner", campaignId: .random, pageRule: "Home")
        ]
        onDoneFetching(messages: givenMessages)

        navigateToScreen(screenName: "Settings")

        // Let's say that the Home screen message finished rendering after we navigate to another screen.
        // When we navigate to the Settings screen, both messages finish rendering after a few seconds on the Settings screen.
        doneLoadingMessage(givenMessages[0])
        doneLoadingMessage(givenMessages[1])

        XCTAssertNil(currentlyShownModalMessage)
        XCTAssertFalse(isCurrentlyLoadingMessage)
    }

    // MARK: clearUserToken

    // Code that runs when the profile is logged out of the SDK

    func test_clearUserToken_givenModalMessageShown_givenModalHasPageRuleSet_expectDismissModal() {
        navigateToScreen(screenName: "Home")

        let givenMessages = [
            Message(messageId: "welcome-banner", campaignId: .random, pageRule: "^(Home)$")
        ]
        onDoneFetching(messages: givenMessages)
        doneLoadingMessage(givenMessages[0])
        XCTAssertNotNil(currentlyShownModalMessage)

        Gist.shared.clearUserToken()

        XCTAssertNil(currentlyShownModalMessage)
    }

    func test_clearUserToken_givenModalMessageShown_givenModalHasNoPageRuleSet_expectDoNotDismissModal() {
        navigateToScreen(screenName: "Home")

        let givenMessages = [
            Message(messageId: "welcome-banner", campaignId: .random, pageRule: nil)
        ]
        onDoneFetching(messages: givenMessages)
        doneLoadingMessage(givenMessages[0])
        XCTAssertNotNil(currentlyShownModalMessage)

        Gist.shared.clearUserToken()

        XCTAssertNotNil(currentlyShownModalMessage)
    }

    // The in-app SDK maintains a cache of messages that are returned from the backend. When a profile is logged out of the SDK, we expect the message cache is cleared otherwise we run the risk of displaying messages meant for profile A to profile B.
    func test_clearUserToken_givenProfileLoggedOutAndNewProfileLoggedIn_expectLocalMessageCacheCleared() {
        Gist.shared.setUserToken("profile-A")

        XCTAssertTrue(Gist.shared.messageQueueManager.localMessageStore.isEmpty)
        setupHttpResponse(code: 200, body: readSampleDataFile(subdirectory: "InAppUserQueue", fileName: "fetch_response.json").data)
        Gist.shared.messageQueueManager.fetchUserMessages()
        XCTAssertFalse(Gist.shared.messageQueueManager.localMessageStore.isEmpty)

        // Expect no messages immediately after logging into another profile.
        Gist.shared.clearUserToken()
        XCTAssertTrue(Gist.shared.messageQueueManager.localMessageStore.isEmpty)
        Gist.shared.setUserToken("profile-B")
        XCTAssertTrue(Gist.shared.messageQueueManager.localMessageStore.isEmpty)

        // Expect that after first fetch with new profile logged in, the message cache remains empty.
        setupHttpResponse(code: 304, body: "".data)
        Gist.shared.messageQueueManager.fetchUserMessages()
        XCTAssertTrue(Gist.shared.messageQueueManager.localMessageStore.isEmpty)
    }

    // MARK: action buttons

    func test_onCloseButton_expectShowNextMessageInQueue() throws {
        navigateToScreen(screenName: "Home")

        let givenMessages = [
            Message(pageRule: "^(Home)$"),
            Message(pageRule: "^(Home)$"),
            Message(pageRule: nil)
        ]

        onDoneFetching(messages: givenMessages)
        doneLoadingMessage(givenMessages[0])
        XCTAssertEqual(currentlyShownModalMessage?.queueId, givenMessages[0].queueId)

        onCloseActionButtonPressed()

        doneLoadingMessage(givenMessages[1])

        XCTAssertEqual(currentlyShownModalMessage?.queueId, givenMessages[1].queueId)

        onCloseActionButtonPressed()

        doneLoadingMessage(givenMessages[2])

        XCTAssertEqual(currentlyShownModalMessage?.queueId, givenMessages[2].queueId)

        onCloseActionButtonPressed()

        XCTAssertNil(currentlyShownModalMessage)
    }

    func test_onCloseButton_givenNextMessageDoesNotMatchPageRule_expectDoNotShowNextMessageInQueue() throws {
        navigateToScreen(screenName: "Home")

        let givenMessages = [
            Message(pageRule: "^(Home)$"),
            Message(pageRule: "^(Settings)$") // expect to not show this message on close.
        ]

        onDoneFetching(messages: givenMessages)
        doneLoadingMessage(givenMessages[0])
        XCTAssertEqual(currentlyShownModalMessage?.queueId, givenMessages[0].queueId)

        onCloseActionButtonPressed()

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

    /*
     The goal of this function is to determine the message that is visible on the screen to the user.
     To try and make the tests the most accurate, access the currently displayed message from the UI layer of the code instead of business logic.
     */
    var currentlyShownModalMessage: Message? {
        // Unfortunately, this method of determining visible modals is not 100% reliable because it still uses the view manager to access the
        // currently visible ViewController. It would be best if we could directly talk to UIKit to access the currently visible ViewController but that's not
        // possible with the current implementation of displaying and dismissing modals in the SDK.
        guard let modalViewManager = Gist.shared.getModalMessageManager()?.modalViewManager else {
            return nil
        }
        if !modalViewManager.isShowingMessage {
            return nil
        }

        return modalViewManager.viewController.gistView.message
    }

    var didCallGlobalEventListener: Bool {
        globalEventListener.messageDismissedCallsCount > 0
    }

    func onDoneFetching(messages: [Message]) {
        Gist.shared.messageQueueManager.processFetchResponse(messages)
    }

    func navigateToScreen(screenName: String) {
        Gist.shared.setCurrentRoute(screenName)
    }

    func doneLoadingMessage(_ message: Message) {
        engineWebMock.underlyingDelegate?.routeLoaded(route: message.messageId)
    }

    func onCloseActionButtonPressed() {
        // Triggering the close button from the web engine simulates the user tapping the close button on the in-app WebView.
        // This behaves more like an integration test because we are also able to test the message manager, too.
        engineWebMock.underlyingDelegate?.tap(name: "", action: GistMessageActions.close.rawValue, system: false)
    }
}
