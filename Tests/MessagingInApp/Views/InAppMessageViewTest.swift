@testable import CioInternalCommon
@testable import CioMessagingInApp
import Foundation
import SharedTests
import XCTest

class InAppMessageViewTest: UnitTest {
    private let queueMock = MessageQueueManagerMock()
    private var engineProvider: EngineWebProviderStub2!

    override func setUp() {
        super.setUp()

        engineProvider = EngineWebProviderStub2()

        DIGraphShared.shared.override(value: queueMock, forType: MessageQueueManager.self)
        DIGraphShared.shared.override(value: engineProvider, forType: EngineWebProvider.self)
    }

    // MARK: View constructed

    @MainActor
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

    @MainActor
    func test_whenViewConstructedUsingStoryboards_expectStartDismissedAfterConstructed() {
        queueMock.getInlineMessagesReturnValue = []

        let view = InAppMessageView(coder: EmptyNSCoder())!

        XCTAssertFalse(isInlineViewVisible(view)) // Assert View is in dismissed state

        view.elementId = .random

        XCTAssertFalse(isInlineViewVisible(view)) // Assert View remains dismissed after setting element id.
    }

    @MainActor
    func test_whenViewConstructedViaCode_expectCheckForMessagesToDisplay() {
        let givenElementId = String.random
        queueMock.getInlineMessagesReturnValue = []

        _ = InAppMessageView(elementId: givenElementId)

        XCTAssertEqual(queueMock.getInlineMessagesCallsCount, 1)

        let actualElementId = queueMock.getInlineMessagesReceivedArguments
        XCTAssertEqual(actualElementId, givenElementId)
    }

    @MainActor
    func test_whenViewConstructedViaCode_expectStartDismissedAfterConstructed() {
        queueMock.getInlineMessagesReturnValue = []

        let view = InAppMessageView(elementId: .random)

        XCTAssertFalse(isInlineViewVisible(view)) // Assert View is in dismissed state
    }

    // MARK: Display in-app message

    @MainActor
    func test_displayInAppMessage_givenNoMessageAvailable_expectDoNotDisplayAMessage() async {
        queueMock.getInlineMessagesReturnValue = []

        let inlineView = InAppMessageView(elementId: .random)

        XCTAssertFalse(isInlineViewVisible(inlineView))
        XCTAssertNil(getInAppMessage(forView: inlineView)) // expect not in process of rendering a message
    }

    @MainActor
    func test_displayInAppMessage_givenMessageAvailable_expectDisplayMessage() async {
        let givenInlineMessage = Message.randomInline
        queueMock.getInlineMessagesReturnValue = [givenInlineMessage]

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        XCTAssertTrue(isInlineViewVisible(inlineView))
        XCTAssertEqual(getInAppMessage(forView: inlineView), givenInlineMessage)
    }

    @MainActor
    func test_displayInAppMessage_givenMultipleMessagesInQueue_expectDisplayFirstMessage() async {
        let givenElementId = String.random
        let givenInlineMessages = [Message(elementId: givenElementId), Message(elementId: givenElementId)]
        queueMock.getInlineMessagesReturnValue = givenInlineMessages

        let inlineView = InAppMessageView(elementId: givenElementId)
        await onDoneRenderingInAppMessage(givenInlineMessages[0], insideOfInlineView: inlineView)

        XCTAssertTrue(isInlineViewVisible(inlineView))
        XCTAssertEqual(getInAppMessage(forView: inlineView), givenInlineMessages[0])
    }

    // MARK: Async fetching of in-app messages

    // The in-app SDK fetches for new messages in the background in an async manner.
    // We need to test that the View is updated when new messages are fetched.

    @MainActor
    func test_givenFirstFetchDoesNotContainAnyMessage_givenInAppMessageFetchedAfterViewConstructed_expectShowInAppMessageFetched() async {
        // start with no messages available.
        queueMock.getInlineMessagesReturnValue = []

        let view = InAppMessageView(elementId: .random)
        XCTAssertFalse(isInlineViewVisible(view))
        XCTAssertNil(getInAppMessage(forView: view)) // expect no message rendering.

        // Modify queue to return a message after the UI has been constructed and not showing a WebView.
        let givenInlineMessage = Message.randomInline
        await simulateSdkFetchedMessages([givenInlineMessage])
        XCTAssertEqual(getInAppMessage(forView: view), givenInlineMessage) // expect to begin rendering message

        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: view)

        XCTAssertTrue(isInlineViewVisible(view))
    }

    // Test that the eventbus listening does not impact memory management of the View instance.
    @MainActor
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

    @MainActor
    func test_givenAlreadyShowingMessage_whenSameMessageFetched_expectDoNotReloadTheMessageAgain() async {
        let givenInlineMessage = Message.randomInline
        queueMock.getInlineMessagesReturnValue = [givenInlineMessage]

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)

        let webViewBeforeFetch = getInAppMessageWebView(fromInlineView: inlineView)

        await simulateSdkFetchedMessages([givenInlineMessage])

        let webViewAfterFetch = getInAppMessageWebView(fromInlineView: inlineView)

        // If the WebViews are the same instance, it means the message was not reloaded.
        XCTAssertTrue(webViewBeforeFetch === webViewAfterFetch)
    }

    @MainActor
    func test_givenAlreadyShowingInAppMessage_whenNewMessageFetched_expectDoNotReplaceContents() async {
        let givenOldInlineMessage = Message.randomInline
        queueMock.getInlineMessagesReturnValue = [givenOldInlineMessage]

        let inlineView = InAppMessageView(elementId: givenOldInlineMessage.elementId!)
        let webViewBeforeFetch = getInAppMessageWebView(fromInlineView: inlineView)

        // Make sure message is a new message, but has same elementId.
        let givenNewInlineMessage = Message(queueId: .random, elementId: givenOldInlineMessage.elementId)

        await simulateSdkFetchedMessages([givenNewInlineMessage])

        let webViewAfterFetch = getInAppMessageWebView(fromInlineView: inlineView)

        // If the WebViews are different, it means the message was reloaded.
        XCTAssertTrue(webViewBeforeFetch === webViewAfterFetch)
        XCTAssertEqual(getInAppMessage(forView: inlineView), givenOldInlineMessage)
    }

    // MARK: expiration of in-app messages

    @MainActor
    func test_expiration_givenDisplayedMessageExpires_expectContinueShowingMessageUntilClose() async {
        let givenInlineMessage = Message.randomInline
        queueMock.getInlineMessagesReturnValue = [givenInlineMessage]

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)

        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        XCTAssertTrue(isInlineViewVisible(inlineView))
        XCTAssertEqual(getInAppMessage(forView: inlineView), givenInlineMessage)

        // Simulate message expiration.
        await simulateSdkFetchedMessages([])

        // Expect still showing the same message as before the fetch call.
        XCTAssertTrue(isInlineViewVisible(inlineView))
        XCTAssertEqual(getInAppMessage(forView: inlineView), givenInlineMessage)

        await onCloseActionButtonPressed(onInlineView: inlineView)

        XCTAssertFalse(isInlineViewVisible(inlineView))
        XCTAssertNil(getInAppMessage(forView: inlineView))
    }

    // MARK: close action button

    @MainActor
    func test_onCloseAction_givenCloseActionClickedOnInAppMessage_expectDismissInlineView() async {
        let givenInlineMessage = Message.randomInline
        queueMock.getInlineMessagesReturnValue = [givenInlineMessage]

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)
        XCTAssertTrue(isInlineViewVisible(inlineView))

        await onCloseActionButtonPressed(onInlineView: inlineView)

        XCTAssertFalse(isInlineViewVisible(inlineView))
        XCTAssertNil(getInAppMessage(forView: inlineView))
    }

    @MainActor
    func test_onCloseAction_givenMultipleMessagesInQueue_expectDisplayNextMessageInQueueAfterClose() async {
        let givenElementId = String.random
        let givenMessages = [Message(elementId: givenElementId), Message(elementId: givenElementId)]
        queueMock.getInlineMessagesReturnValue = givenMessages

        let view = InAppMessageView(elementId: givenElementId)

        await onDoneRenderingInAppMessage(givenMessages[0], insideOfInlineView: view)
        XCTAssertTrue(isInlineViewVisible(view))
        XCTAssertEqual(getInAppMessage(forView: view), givenMessages[0])

        await onCloseActionButtonPressed(onInlineView: view)
        await onDoneRenderingInAppMessage(givenMessages[1], insideOfInlineView: view)
        XCTAssertTrue(isInlineViewVisible(view))
        XCTAssertEqual(getInAppMessage(forView: view), givenMessages[1])

        await onCloseActionButtonPressed(onInlineView: view)
        XCTAssertFalse(isInlineViewVisible(view))
        XCTAssertNil(getInAppMessage(forView: view))
    }

    @MainActor
    func test_onCloseAction_givenMessageClosed_givenNewMessageFetched_expectDisplayNewMessage() async {
        let givenMessageThatGetsClosed = Message.randomInline
        let givenNewMessageFetched = Message.randomInline
        queueMock.getInlineMessagesReturnValue = [givenMessageThatGetsClosed]

        let inlineView = InAppMessageView(elementId: givenMessageThatGetsClosed.elementId!)
        await onDoneRenderingInAppMessage(givenMessageThatGetsClosed, insideOfInlineView: inlineView)
        XCTAssertTrue(isInlineViewVisible(inlineView))
        await onCloseActionButtonPressed(onInlineView: inlineView)
        XCTAssertFalse(isInlineViewVisible(inlineView))
        XCTAssertNil(getInAppMessage(forView: inlineView))

        await simulateSdkFetchedMessages([givenNewMessageFetched]) // simulate new message fetched
        XCTAssertEqual(getInAppMessage(forView: inlineView), givenNewMessageFetched) // expect to begin rendering new message
        await onDoneRenderingInAppMessage(givenNewMessageFetched, insideOfInlineView: inlineView)
        XCTAssertTrue(isInlineViewVisible(inlineView)) // expect show next message once it's done rendering
    }

    @MainActor
    func test_onCloseAction_givenMultipleViewInstances_givenCloseMessageOnOneView_expectOtherViewStillShowingOriginalMessage() async {
        let givenElementId = String.random
        let givenMessages = [Message(elementId: givenElementId)]
        queueMock.getInlineMessagesReturnValue = givenMessages

        let inlineView1 = InAppMessageView(elementId: givenElementId)
        let inlineView2 = InAppMessageView(elementId: givenElementId)

        await onDoneRenderingInAppMessage(givenMessages[0], insideOfInlineView: inlineView1)
        await onDoneRenderingInAppMessage(givenMessages[0], insideOfInlineView: inlineView2)
        XCTAssertEqual(getInAppMessage(forView: inlineView1), givenMessages[0])
        XCTAssertEqual(getInAppMessage(forView: inlineView2), givenMessages[0])

        await onCloseActionButtonPressed(onInlineView: inlineView1)
        XCTAssertNil(getInAppMessage(forView: inlineView1))
        XCTAssertEqual(getInAppMessage(forView: inlineView2), givenMessages[0])
    }

    // MARK: height and width constriants

    // When the View is constructed, the SDK will add a constraint or it will modify the existing height constraint.
    // A View should not have multiple height constraints, which is why we document the SDK behavior around height constraints.
    //
    // This test function hightlights a behavior that could happen, but we don't expect it to according to our documentation of the inline View.
    @MainActor
    func test_heightAndWidth_givenUserSetsHeightConstraint_expectSdkAddsASeparateConstraint() async {
        queueMock.getInlineMessagesReturnValue = []

        let givenHeightUserSetsOnView: CGFloat = 100
        let givenWidthUserSetsOnView: CGFloat = 100

        let view = InAppMessageView(elementId: .random)
        // After the constructor is called, the SDK has already created a height constraint if one does not yet exist.
        // Then, the customer may decide to create another one, although our documentation suggests not to.
        NSLayoutConstraint.activate([view.heightAnchor.constraint(equalToConstant: givenHeightUserSetsOnView)])
        NSLayoutConstraint.activate([view.widthAnchor.constraint(equalToConstant: givenWidthUserSetsOnView)])

        await simulateSdkFetchedMessages([])

        // Expects that the View has 2 height constraints: Sdk added and customer added.
        XCTAssertEqual(view.heightConstraints.map(\.constant), [0, 100])
        XCTAssertEqual(view.widthConstraints.map(\.constant), [givenWidthUserSetsOnView])
    }

    @MainActor
    func test_heightAndWidth_givenViewDisplaysMessage_expectSdkModifiesTheHeightToSizeOfMessage() async {
        queueMock.getInlineMessagesReturnValue = [] // start with no messages available

        let givenWidthUserSetsOnView: CGFloat = 100

        let view = InAppMessageView(elementId: .random)
        NSLayoutConstraint.activate([view.widthAnchor.constraint(equalToConstant: givenWidthUserSetsOnView)])

        // The SDK fetches a message and renders it. We expect the View displays this message.
        let givenInlineMessage = Message.randomInline
        await simulateSdkFetchedMessages([givenInlineMessage])
        // The width of the rendered message is expected to equal what the customer sets the View for. We do not modify the View's width.
        // Notice the height of the rendered Message is different from what the customer set the View.
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: view, heightOfRenderedMessage: 300, widthOfRenderedMessage: givenWidthUserSetsOnView)

        // We expect the SDK modifies the View's height, but not the width.
        // We expect to see 1 height constraint which is the one added by the SDK.
        XCTAssertEqual(view.heightConstraints.map(\.constant), [300])
        XCTAssertEqual(view.widthConstraints.map(\.constant), [givenWidthUserSetsOnView])
    }

    @MainActor
    func test_heightAndWidth_givenNoMessageToDisplay_expectSdkModifiesTheHeightToNotShowView() async {
        queueMock.getInlineMessagesReturnValue = []

        let givenWidthUserSetsOnView: CGFloat = 100

        let view = InAppMessageView(elementId: .random)
        NSLayoutConstraint.activate([view.widthAnchor.constraint(equalToConstant: givenWidthUserSetsOnView)])

        // We expect the SDK modifies the View's height, but not the width.
        // We expect to see 1 height constraint which is the one added by the SDK.
        XCTAssertEqual(view.heightConstraints.map(\.constant), [0])
        XCTAssertEqual(view.widthConstraints.map(\.constant), [givenWidthUserSetsOnView])
    }
}

@MainActor
extension InAppMessageViewTest {
    // Only tells you if the View is visible in the UI to the user. Does not tell you if the View is in the process of rendering a message.
    func isInlineViewVisible(_ view: InAppMessageView) -> Bool {
        guard let viewHeightConstraint = view.heightConstraint else {
            return false
        }

        return viewHeightConstraint.constant > 0
    }

    // Tells you the message the Inline View is either rendering or has already rendered.
    func getInAppMessage(forView view: InAppMessageView) -> Message? {
        getInAppMessageWebView(fromInlineView: view)?.message
    }

    func onCloseActionButtonPressed(onInlineView inlineView: InAppMessageView) async {
        // Triggering the close button from the web engine simulates the user tapping the close button on the in-app WebView.
        // This behaves more like an integration test because we are also able to test the message manager, too.
        getWebEngineForInlineView(inlineView)?.delegate?.tap(name: "", action: GistMessageActions.close.rawValue, system: false)

        // When onCloseAction() is called on the inline View, it adds a task to the main thread queue. Our test wants to wait until this task is done running.
        await waitForMainThreadToFinishPendingTasks()
    }

    // Call when the in-app webview rendering process has finished.
    func onDoneRenderingInAppMessage(_ message: Message, insideOfInlineView inlineView: InAppMessageView, heightOfRenderedMessage: CGFloat = 100, widthOfRenderedMessage: CGFloat = 100) async {
        // The engine is like a HTTP layer in that it calls the Gist web server to get back rendered in-app messages.
        // To mock the web server call with a successful response back, call these delegate functions:
        getWebEngineForInlineView(inlineView)?.delegate?.routeLoaded(route: message.templateId)
        getWebEngineForInlineView(inlineView)?.delegate?.sizeChanged(width: widthOfRenderedMessage, height: heightOfRenderedMessage)

        // When sizeChanged() is called on the inline View, it adds a task to the main thread queue. Our test wants to wait until this task is done running.
        await waitForMainThreadToFinishPendingTasks()
    }

    func getWebEngineForInlineView(_ view: InAppMessageView) -> EngineWebInstance? {
        view.inlineMessageManager?.engine
    }

    func getInAppMessageWebView(fromInlineView view: InAppMessageView) -> GistView? {
        let gistViews: [GistView] = view.subviews.map { $0 as? GistView }.mapNonNil()

        if gistViews.isEmpty {
            return nil
        }

        XCTAssertEqual(gistViews.count, 1)

        return gistViews.first
    }

    func simulateSdkFetchedMessages(_ messages: [Message]) async {
        // Because eventbus operations are async, use an expectation that waits until eventbus event is posted and observer is called.
        let expectToCheckIfInAppMessagesAvailableToDisplay = expectation(description: "expect to check for in-app messages")

        queueMock.getInlineMessagesClosure = { [weak expectToCheckIfInAppMessagesAvailableToDisplay] _ in
            expectToCheckIfInAppMessagesAvailableToDisplay?.fulfill()

            return messages
        }
        // Imagine the in-app SDK has fetched new messages. It sends an event to the eventbus.
        DIGraphShared.shared.eventBusHandler.postEvent(InAppMessagesFetchedEvent())
        await waitForExpectations([expectToCheckIfInAppMessagesAvailableToDisplay])
    }
}
