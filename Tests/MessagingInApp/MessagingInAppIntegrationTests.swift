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
            Message(messageId: "welcome-banner", campaignId: .random, pageRule: "Home")
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
            Message(messageId: "welcome-banner", campaignId: .random, pageRule: "Home")
        ]

        onDoneFetching(messages: givenMessages)
        doneLoadingMessage(givenMessages[0])
        XCTAssertEqual(currentlyShownModalMessage?.instanceId, givenMessages[0].instanceId)

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
}
