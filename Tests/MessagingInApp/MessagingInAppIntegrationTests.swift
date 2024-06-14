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
        Gist.shared.messageQueueManager.processFetchResponse(messages)
    }

    func navigateToScreen(screenName: String) {
        Gist.shared.setCurrentRoute(screenName)
    }

    func doneLoadingMessage(_ message: Message) {
        engineWebMock.underlyingDelegate?.routeLoaded(route: message.messageId)
    }
}
