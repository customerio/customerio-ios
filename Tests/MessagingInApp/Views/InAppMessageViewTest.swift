@testable import CioInternalCommon
@testable import CioMessagingInApp
import Foundation
import SharedTests
import XCTest

class InAppMessageViewTest: UnitTest {
    private let queueMock = MessageQueueManagerMock()

    override func setUp() {
        super.setUp()

        DIGraphShared.shared.override(value: queueMock, forType: MessageQueueManager.self)
    }

    // MARK: View constructed

    func test_whenViewConstructedUsingStoryboards_expectCheckForMessagesToDisplay() {
        let view = InAppMessageView(coder: EmptyNSCoder())!

        // We do not check messages until elementId is set.
        XCTAssertFalse(queueMock.mockCalled)

        let givenElementId = String.random
        queueMock.getInlineMessagesReturnValue = []

        view.elementId = givenElementId

        XCTAssertEqual(queueMock.getInlineMessagesCallsCount, 1)

        let actualElementId = queueMock.getInlineMessagesReceivedArguments
        XCTAssertEqual(actualElementId, givenElementId)
    }

    func test_whenViewConstructedViaCode_expectCheckForMessagesToDisplay() {
        let givenElementId = String.random
        queueMock.getInlineMessagesReturnValue = []

        _ = InAppMessageView(elementId: givenElementId)

        XCTAssertEqual(queueMock.getInlineMessagesCallsCount, 1)

        let actualElementId = queueMock.getInlineMessagesReceivedArguments
        XCTAssertEqual(actualElementId, givenElementId)
    }

    // MARK: Display in-app message

    func test_displayInAppMessage_givenNoMessageAvailable_expectDoNotDisplayAMessage() {
        queueMock.getInlineMessagesReturnValue = []

        let inlineView = InAppMessageView(elementId: .random)

        XCTAssertNil(getInAppMessageWebView(fromInlineView: inlineView))
    }

    func test_displayInAppMessage_givenMessageAvailable_expectDisplayMessage() {
        let givenInlineMessage = Message.randomInline
        queueMock.getInlineMessagesReturnValue = [givenInlineMessage]

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)

        XCTAssertNotNil(getInAppMessageWebView(fromInlineView: inlineView))
    }

    // MARK: Async fetching of in-app messages

    // The in-app SDK fetches for new messages in the background in an async manner.
    // We need to test that the View is updated when new messages are fetched.

    func test_givenInAppMessageFetchedAfterViewConstructed_expectShowInAppMessageFetched() {
        // start with no messages available.
        queueMock.getInlineMessagesReturnValue = []

        let view = InAppMessageView(elementId: .random)
        XCTAssertNil(getInAppMessageWebView(fromInlineView: view))

        // Modify queue to return a message after the UI has been constructed and not showing a WebView.
        simulateSdkFetchedMessages([Message.random])

        XCTAssertNotNil(getInAppMessageWebView(fromInlineView: view))
    }

    // Test that the eventbus listening does not impact memory management of the View instance.
    func test_deinit_givenObservingEventBusEvent_expectNoMemoryLeaks() {
        // Before we try to deinit the View, make sure the eventbus observer has executed at least once.
        // This is important if the observer holds a strong reference to something preventing the View deinit.
        let expectToCheckIfInAppMessagesAvailableToDisplay = expectation(description: "expect to check for in-app messages")
        expectToCheckIfInAppMessagesAvailableToDisplay.expectedFulfillmentCount = 2 // once on View init() and once on observer action.
        queueMock.getInlineMessagesClosure = { _ in
            expectToCheckIfInAppMessagesAvailableToDisplay.fulfill()
            return []
        }

        var view: InAppMessageView? = InAppMessageView(elementId: .random)

        DIGraphShared.shared.eventBusHandler.postEvent(InAppMessagesFetchedEvent())

        // Wait for the observer to be called.
        waitForExpectations()

        // Deinit the View and asert deinit actually cleared the instance.
        view = nil
        XCTAssertNil(view)
    }

    func test_givenAlreadyShowingInAppMessage_whenNewMessageFetched_expectShowNewMessage() {
        let givenOldInlineMessage = Message.randomInline
        queueMock.getInlineMessagesReturnValue = [givenOldInlineMessage]

        let inlineView = InAppMessageView(elementId: givenOldInlineMessage.elementId!)
        let webViewBeforeFetch = getInAppMessageWebView(fromInlineView: inlineView)

        // Make sure message is unique, but has same elementId.
        let givenNewInlineMessage = Message(messageId: .random, campaignId: .random, elementId: givenOldInlineMessage.elementId)

        simulateSdkFetchedMessages([givenNewInlineMessage])

        let webViewAfterFetch = getInAppMessageWebView(fromInlineView: inlineView)

        // If the WebViews are different, it means the message was reloaded.
        XCTAssertTrue(webViewBeforeFetch !== webViewAfterFetch)
    }

    func test_givenAlreadyShowingMessage_whenSameMessageFetched_expectDoNotReloadTheMessageAgain() {
        let givenInlineMessage = Message.randomInline
        queueMock.getInlineMessagesReturnValue = [givenInlineMessage]

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)

        let webViewBeforeFetch = getInAppMessageWebView(fromInlineView: inlineView)

        simulateSdkFetchedMessages([givenInlineMessage])

        let webViewAfterFetch = getInAppMessageWebView(fromInlineView: inlineView)

        // If the WebViews are the same instance, it means the message was not reloaded.
        XCTAssertTrue(webViewBeforeFetch === webViewAfterFetch)
    }
}

extension InAppMessageViewTest {
    func getInAppMessageWebView(fromInlineView view: InAppMessageView) -> GistView? {
        let gistViews: [GistView] = view.subviews.map { $0 as? GistView }.mapNonNil()

        if gistViews.isEmpty {
            return nil
        }

        XCTAssertEqual(gistViews.count, 1)

        return gistViews.first
    }

    func simulateSdkFetchedMessages(_ messages: [Message]) {
        // Because eventbus operations are async, use an expectation that waits until eventbus event is posted and observer is called.
        let expectToCheckIfInAppMessagesAvailableToDisplay = expectation(description: "expect to check for in-app messages")
        queueMock.getInlineMessagesClosure = { _ in
            expectToCheckIfInAppMessagesAvailableToDisplay.fulfill()
            return messages
        }
        // Imagine the in-app SDK has fetched new messages. It sends an event to the eventbus.
        DIGraphShared.shared.eventBusHandler.postEvent(InAppMessagesFetchedEvent())
        waitForExpectations()
    }
}
