@testable import CioInternalCommon
@testable import CioMessagingInApp
import Foundation
import SharedTests
import XCTest

class InAppMessageViewTest: IntegrationTest {
    private let engineWebMock = EngineWebInstanceMock()
    private let inlineMessageDelegateMock = InAppMessageViewActionDelegateMock()
    private let eventListenerMock = InAppEventListenerMock()
    private let deeplinkUtilMock = DeepLinkUtilMock()

    private var eventBusMetricsTracked: [TrackInAppMetricEvent] = []

    override func setUp() {
        // We want to assert metrics are tracked, but we don't want to mock the eventbus for our integration test in this class.
        // Therefore, listen for real events being posted to verify in the test functions.
        eventBusMetricsTracked = []
        diGraphShared.eventBusHandler.addObserver(TrackInAppMetricEvent.self) { event in
            self.eventBusMetricsTracked.append(event)
        }

        super.setUp()

        // Set a random user token so that the SDK can perform fetches for user messages.
        UserManager().setUserToken(userToken: .random)

        DIGraphShared.shared.override(value: deeplinkUtilMock, forType: DeepLinkUtil.self)

        messagingInAppImplementation.setEventListener(eventListenerMock)
    }

    // MARK: View constructed

    @MainActor
    func test_whenViewConstructedUsingStoryboards_expectCheckForMessagesToDisplay() {
        let queueMock = setupQueueMock()

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
        let queueMock = setupQueueMock()
        queueMock.getInlineMessagesReturnValue = []

        let view = InAppMessageView(coder: EmptyNSCoder())!

        XCTAssertFalse(isInlineViewVisible(view)) // Assert View is in dismissed state

        view.elementId = .random

        XCTAssertFalse(isInlineViewVisible(view)) // Assert View remains dismissed after setting element id.
    }

    @MainActor
    func test_whenViewConstructedViaCode_expectCheckForMessagesToDisplay() {
        let queueMock = setupQueueMock()
        let givenElementId = String.random
        queueMock.getInlineMessagesReturnValue = []

        _ = InAppMessageView(elementId: givenElementId)

        XCTAssertEqual(queueMock.getInlineMessagesCallsCount, 1)

        let actualElementId = queueMock.getInlineMessagesReceivedArguments
        XCTAssertEqual(actualElementId, givenElementId)
    }

    @MainActor
    func test_whenViewConstructedViaCode_expectStartDismissedAfterConstructed() {
        let queueMock = setupQueueMock()
        queueMock.getInlineMessagesReturnValue = []

        let view = InAppMessageView(elementId: .random)

        XCTAssertFalse(isInlineViewVisible(view)) // Assert View is in dismissed state
    }

    // MARK: Display in-app message

    @MainActor
    func test_displayInAppMessage_givenNoMessageAvailable_expectDoNotDisplayAMessage() async {
        await simulateSdkFetchedMessages([], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: .random)

        XCTAssertFalse(isInlineViewVisible(inlineView))
        XCTAssertNil(getInAppMessage(forView: inlineView)) // expect not in process of rendering a message
    }

    @MainActor
    func test_displayInAppMessage_givenMessageAvailable_expectDisplayMessage() async {
        let givenInlineMessage = Message.randomInline
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        XCTAssertTrue(isInlineViewVisible(inlineView))
        XCTAssertEqual(getInAppMessage(forView: inlineView), givenInlineMessage)
        assert(view: inlineView.inAppMessageView, isShowing: true, inInlineView: inlineView)
    }

    @MainActor
    func test_displayInAppMessage_givenMultipleMessagesInQueue_expectDisplayFirstMessage() async {
        let givenElementId = String.random
        let givenInlineMessages = [Message(elementId: givenElementId), Message(elementId: givenElementId)]

        await simulateSdkFetchedMessages(givenInlineMessages, verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenElementId)

        await onDoneRenderingInAppMessage(givenInlineMessages[0], insideOfInlineView: inlineView)

        XCTAssertTrue(isInlineViewVisible(inlineView))
        XCTAssertEqual(getInAppMessage(forView: inlineView), givenInlineMessages[0])
        assert(view: inlineView.inAppMessageView, isShowing: true, inInlineView: inlineView)
    }

    @MainActor
    func test_givenAttemptToShowInlineMessageFails_expectMessageNotShown() async {
        let givenInlineMessage = Message.randomInline
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        await onDoneRenderingInAppMessageWithError(givenInlineMessage, insideOfInlineView: inlineView)

        // Inline message does not display
        XCTAssertFalse(isInlineViewVisible(inlineView))
    }

    // MARK: Async fetching of in-app messages

    // The in-app SDK fetches for new messages in the background in an async manner.
    // We need to test that the View is updated when new messages are fetched.

    @MainActor
    func test_givenFirstFetchDoesNotContainAnyMessage_givenInAppMessageFetchedAfterViewConstructed_expectShowInAppMessageFetched() async {
        let givenElementId = String.random
        // start with no messages available.
        await simulateSdkFetchedMessages([], verifyInlineViewNotifiedOfFetch: nil)

        let view = InAppMessageView(elementId: givenElementId)
        XCTAssertFalse(isInlineViewVisible(view))
        XCTAssertNil(getInAppMessage(forView: view)) // expect no message rendering.

        // Modify queue to return a message after the UI has been constructed and not showing a WebView.
        let givenInlineMessage = Message(elementId: givenElementId)
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: view)
        XCTAssertEqual(getInAppMessage(forView: view), givenInlineMessage) // expect to begin rendering message

        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: view)

        XCTAssertTrue(isInlineViewVisible(view))
        assert(view: view.inAppMessageView, isShowing: true, inInlineView: view)
    }

    // Test that the eventbus listening does not impact memory management of the View instance.
    @MainActor
    func test_deinit_givenObservingEventBusEvent_expectNoMemoryLeaks() {
        let queueMock = setupQueueMock()

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
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)

        let webViewBeforeFetch = inlineView.inAppMessageView

        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: inlineView)

        let webViewAfterFetch = inlineView.inAppMessageView

        // If the WebViews are the same instance, it means the message was not reloaded.
        XCTAssertTrue(webViewBeforeFetch === webViewAfterFetch)
    }

    @MainActor
    func test_givenAlreadyShowingInAppMessage_whenNewMessageFetched_expectDoNotReplaceContents() async {
        let givenOldInlineMessage = Message.randomInline
        await simulateSdkFetchedMessages([givenOldInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenOldInlineMessage.elementId!)
        let webViewBeforeFetch = inlineView.inAppMessageView

        // Make sure message is a new message, but has same elementId.
        let givenNewInlineMessage = Message(queueId: .random, elementId: givenOldInlineMessage.elementId)

        await simulateSdkFetchedMessages([givenNewInlineMessage], verifyInlineViewNotifiedOfFetch: inlineView)

        let webViewAfterFetch = inlineView.inAppMessageView

        // If the WebViews are different, it means the message was reloaded.
        XCTAssertTrue(webViewBeforeFetch === webViewAfterFetch)
        XCTAssertEqual(getInAppMessage(forView: inlineView), givenOldInlineMessage)
    }

    // MARK: expiration of in-app messages

    @MainActor
    func test_expiration_givenDisplayedMessageExpires_expectContinueShowingMessageUntilClose() async {
        let givenInlineMessage = Message.randomInline
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)

        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        XCTAssertTrue(isInlineViewVisible(inlineView))
        XCTAssertEqual(getInAppMessage(forView: inlineView), givenInlineMessage)

        // Simulate message expiration.
        await simulateSdkFetchedMessages([], verifyInlineViewNotifiedOfFetch: inlineView)

        // Expect still showing the same message as before the fetch call.
        XCTAssertTrue(isInlineViewVisible(inlineView))
        XCTAssertEqual(getInAppMessage(forView: inlineView), givenInlineMessage)

        await onCloseActionButtonPressed(onInlineView: inlineView)

        XCTAssertFalse(isInlineViewVisible(inlineView))
        XCTAssertNil(getInAppMessage(forView: inlineView))
    }

    @MainActor
    func test_expiration_givenExpiredMessageNotYetDisplayed_expectDoNotDisplayMessage() async {
        let givenMessageDisplayed = Message(elementId: .random)
        let givenMessageThatExpires = Message(elementId: .random)
        await simulateSdkFetchedMessages([givenMessageDisplayed, givenMessageThatExpires], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenMessageDisplayed.elementId!)

        await onDoneRenderingInAppMessage(givenMessageDisplayed, insideOfInlineView: inlineView)

        XCTAssertTrue(isInlineViewVisible(inlineView))
        XCTAssertEqual(getInAppMessage(forView: inlineView), givenMessageDisplayed)

        // Simulate message expiration.
        await simulateSdkFetchedMessages([givenMessageDisplayed], verifyInlineViewNotifiedOfFetch: inlineView)

        // Expect still showing the same message as before the fetch call.
        XCTAssertEqual(getInAppMessage(forView: inlineView), givenMessageDisplayed)

        await onCloseActionButtonPressed(onInlineView: inlineView)

        // Expect we do not show the expired message but instead close the View.
        XCTAssertFalse(isInlineViewVisible(inlineView))
        XCTAssertNil(getInAppMessage(forView: inlineView))
    }

    // MARK: close action button

    @MainActor
    func test_onCloseAction_givenCloseActionClickedOnInAppMessage_expectDismissInlineView() async {
        let givenInlineMessage = Message.randomInline
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

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
        await simulateSdkFetchedMessages(givenMessages, verifyInlineViewNotifiedOfFetch: nil)

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
    func test_onCloseAction_givenMultipleMessagesInQueue_expectShowLoadingViewWhileRenderingNextMessage() async {
        let givenElementId = String.random
        let givenMessages = [Message(elementId: givenElementId), Message(elementId: givenElementId)]
        await simulateSdkFetchedMessages(givenMessages, verifyInlineViewNotifiedOfFetch: nil)

        let view = InAppMessageView(elementId: givenElementId)

        // On first message, expect the loading view to be hidden
        await onDoneRenderingInAppMessage(givenMessages[0], insideOfInlineView: view)
        XCTAssertTrue(isInlineViewVisible(view))
        assert(view: view.inAppMessageView, isShowing: true, inInlineView: view)
        assert(view: view.messageRenderingLoadingView, isShowing: false, inInlineView: view)

        // On close, expect the loading view to be shown while rendering the next message
        await onCloseActionButtonPressed(onInlineView: view)
        XCTAssertTrue(isInlineViewVisible(view))
        assert(view: view.messageRenderingLoadingView, isShowing: true, inInlineView: view)
        assert(view: view.inAppMessageView, isShowing: false, inInlineView: view)

        // After rendering the next message, expect the loading view to be hidden
        await onDoneRenderingInAppMessage(givenMessages[1], insideOfInlineView: view)
        XCTAssertTrue(isInlineViewVisible(view))
        assert(view: view.inAppMessageView, isShowing: true, inInlineView: view)
        assert(view: view.messageRenderingLoadingView, isShowing: false, inInlineView: view)

        // On close, expect the inline view to be hidden
        await onCloseActionButtonPressed(onInlineView: view)
        XCTAssertFalse(isInlineViewVisible(view))
    }

    @MainActor
    func test_onCloseAction_givenMessageClosed_givenNewMessageFetched_expectDisplayNewMessage() async {
        let givenElementId = String.random
        let givenMessageThatGetsClosed = Message(elementId: givenElementId)
        let givenNewMessageFetched = Message(elementId: givenElementId)
        await simulateSdkFetchedMessages([givenMessageThatGetsClosed], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenMessageThatGetsClosed.elementId!)
        await onDoneRenderingInAppMessage(givenMessageThatGetsClosed, insideOfInlineView: inlineView)
        XCTAssertTrue(isInlineViewVisible(inlineView))
        await onCloseActionButtonPressed(onInlineView: inlineView)
        XCTAssertFalse(isInlineViewVisible(inlineView))
        XCTAssertNil(getInAppMessage(forView: inlineView))

        await simulateSdkFetchedMessages([givenNewMessageFetched], verifyInlineViewNotifiedOfFetch: inlineView) // simulate new message fetched
        XCTAssertEqual(getInAppMessage(forView: inlineView), givenNewMessageFetched) // expect to begin rendering new message
        await onDoneRenderingInAppMessage(givenNewMessageFetched, insideOfInlineView: inlineView)
        XCTAssertTrue(isInlineViewVisible(inlineView)) // expect show next message once it's done rendering
    }

    @MainActor
    func test_onCloseAction_givenMultipleViewInstances_givenCloseMessageOnOneView_expectOtherViewStillShowingOriginalMessage() async {
        let givenElementId = String.random
        let givenMessages = [Message(elementId: givenElementId)]
        await simulateSdkFetchedMessages(givenMessages, verifyInlineViewNotifiedOfFetch: nil)

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
        await simulateSdkFetchedMessages([], verifyInlineViewNotifiedOfFetch: nil)

        let givenHeightUserSetsOnView: CGFloat = 100
        let givenWidthUserSetsOnView: CGFloat = 100

        let view = InAppMessageView(elementId: .random)
        // After the constructor is called, the SDK has already created a height constraint if one does not yet exist.
        // Then, the customer may decide to create another one, although our documentation suggests not to.
        NSLayoutConstraint.activate([view.heightAnchor.constraint(equalToConstant: givenHeightUserSetsOnView)])
        NSLayoutConstraint.activate([view.widthAnchor.constraint(equalToConstant: givenWidthUserSetsOnView)])

        await simulateSdkFetchedMessages([], verifyInlineViewNotifiedOfFetch: view)

        // Expects that the View has 2 height constraints: Sdk added and customer added.
        XCTAssertEqual(view.heightConstraints.map(\.constant), [0, 100])
        XCTAssertEqual(view.widthConstraints.map(\.constant), [givenWidthUserSetsOnView])
    }

    @MainActor
    func test_heightAndWidth_givenViewDisplaysMessage_expectSdkModifiesTheHeightToSizeOfMessage() async {
        let givenElementId = String.random

        await simulateSdkFetchedMessages([], verifyInlineViewNotifiedOfFetch: nil) // start with no messages available

        let givenWidthUserSetsOnView: CGFloat = 100

        let view = InAppMessageView(elementId: givenElementId)
        NSLayoutConstraint.activate([view.widthAnchor.constraint(equalToConstant: givenWidthUserSetsOnView)])

        // The SDK fetches a message and renders it. We expect the View displays this message.
        let givenInlineMessage = Message(elementId: givenElementId)
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: view)
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
        await simulateSdkFetchedMessages([], verifyInlineViewNotifiedOfFetch: nil)

        let givenWidthUserSetsOnView: CGFloat = 100

        let view = InAppMessageView(elementId: .random)
        NSLayoutConstraint.activate([view.widthAnchor.constraint(equalToConstant: givenWidthUserSetsOnView)])

        // We expect the SDK modifies the View's height, but not the width.
        // We expect to see 1 height constraint which is the one added by the SDK.
        XCTAssertEqual(view.heightConstraints.map(\.constant), [0])
        XCTAssertEqual(view.widthConstraints.map(\.constant), [givenWidthUserSetsOnView])
    }

    // MARK: - custom action button

    @MainActor
    func test_onInlineButtonAction_givenDelegateSet_expectCustomCallback() async {
        let givenInlineMessage = Message.randomInline
        let gistInAppInlineMessage = InAppMessage(gistMessage: givenInlineMessage)
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        inlineView.onActionDelegate = inlineMessageDelegateMock
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        XCTAssertTrue(isInlineViewVisible(inlineView))
        await onCustomActionButtonPressed(onInlineView: inlineView)

        XCTAssertTrue(inlineMessageDelegateMock.onActionClickCalled)
        XCTAssertEqual(inlineMessageDelegateMock.onActionClickReceivedArguments?.message, gistInAppInlineMessage)
        XCTAssertEqual(inlineMessageDelegateMock.onActionClickReceivedArguments?.actionValue, "Test")
        XCTAssertEqual(inlineMessageDelegateMock.onActionClickReceivedArguments?.actionName, "")

        // Also check that the global listener is not called
        XCTAssertFalse(eventListenerMock.messageActionTakenCalled)
    }

    @MainActor
    func test_onInlineButtonAction_givenDelegateNotSet_expectGlobalCallback() async {
        let givenInlineMessage = Message.randomInline
        let gistInAppInlineMessage = InAppMessage(gistMessage: givenInlineMessage)
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        XCTAssertTrue(isInlineViewVisible(inlineView))
        await onCustomActionButtonPressed(onInlineView: inlineView)

        XCTAssertFalse(inlineMessageDelegateMock.onActionClickCalled)
        XCTAssertTrue(eventListenerMock.messageActionTakenCalled)
        XCTAssertEqual(eventListenerMock.messageActionTakenReceivedArguments?.message, gistInAppInlineMessage)
        XCTAssertEqual(eventListenerMock.messageActionTakenReceivedArguments?.actionValue, "Test")
        XCTAssertEqual(eventListenerMock.messageActionTakenReceivedArguments?.actionName, "")
    }

    @MainActor
    func test_onInlineButtonAction_multipleInlineMessages_givenDelegateSetForAll_expectSingleCustomCallback() async {
        let givenInlineMessage1 = Message.randomInline
        let gistInAppInlineMessage1 = InAppMessage(gistMessage: givenInlineMessage1)

        let givenInlineMessage2 = Message.randomInline
        await simulateSdkFetchedMessages([givenInlineMessage1, givenInlineMessage2], verifyInlineViewNotifiedOfFetch: nil)

        let inlineActionDelegate1 = InAppMessageViewActionDelegateMock()
        let inlineActionDelegate2 = InAppMessageViewActionDelegateMock()
        // Create two inline in app views and assign individual delegates
        let inlineView1 = InAppMessageView(elementId: givenInlineMessage1.elementId!)
        inlineView1.onActionDelegate = inlineActionDelegate1
        let inlineView2 = InAppMessageView(elementId: givenInlineMessage2.elementId!)
        inlineView2.onActionDelegate = inlineActionDelegate2

        // Render both the views
        await onDoneRenderingInAppMessage(givenInlineMessage1, insideOfInlineView: inlineView1)
        await onDoneRenderingInAppMessage(givenInlineMessage2, insideOfInlineView: inlineView2)

        // Both are visible
        XCTAssertTrue(isInlineViewVisible(inlineView1))
        XCTAssertTrue(isInlineViewVisible(inlineView2))

        // Trigger button tap on one of the views
        await onCustomActionButtonPressed(onInlineView: inlineView1)

        // Check that only inlineActionDelegate1's delegate method is called
        XCTAssertFalse(inlineActionDelegate2.mockCalled)
        XCTAssertTrue(inlineActionDelegate1.onActionClickCalled)

        // Check that the button is called once and values received as parameters
        // match the view that triggered the button tap
        XCTAssertTrue(inlineActionDelegate1.onActionClickCalled)
        XCTAssertEqual(inlineActionDelegate1.onActionClickCallsCount, 1)

        XCTAssertFalse(eventListenerMock.messageActionTakenCalled)

        XCTAssertEqual(inlineActionDelegate1.onActionClickReceivedArguments?.message, gistInAppInlineMessage1)
        XCTAssertEqual(inlineActionDelegate1.onActionClickReceivedArguments?.actionValue, "Test")
        XCTAssertEqual(inlineActionDelegate1.onActionClickReceivedArguments?.actionName, "")
    }

    // MARK: "Show another message" action buttons

    @MainActor
    func test_showAnotherMessageAction_givenClickActionButton_expectShowLoadingViewAfterClickButton() async {
        let givenMessage = Message.randomInline
        await simulateSdkFetchedMessages([givenMessage], verifyInlineViewNotifiedOfFetch: nil)

        let view = InAppMessageView(elementId: givenMessage.elementId!)

        await onDoneRenderingInAppMessage(givenMessage, insideOfInlineView: view)
        assert(view: view.inAppMessageView, isShowing: true, inInlineView: view)

        await onShowAnotherMessageActionButtonPressed(onInlineView: view)

        // Expect that the loading view is shown after click button.
        assert(view: view.messageRenderingLoadingView, isShowing: true, inInlineView: view)
    }

    @MainActor
    func test_showAnotherMessageAction_givenNewMessageFinishesRendering_expectToDisplayMessage() async {
        let givenMessage = Message.randomInline
        await simulateSdkFetchedMessages([givenMessage], verifyInlineViewNotifiedOfFetch: nil)

        let view = InAppMessageView(elementId: givenMessage.elementId!)

        await onDoneRenderingInAppMessage(givenMessage, insideOfInlineView: view)
        assert(view: view.inAppMessageView, isShowing: true, inInlineView: view)

        let givenNewMessageToShow = Message(templateId: .random)
        await onShowAnotherMessageActionButtonPressed(onInlineView: view, newMessageTemplateId: givenNewMessageToShow.templateId)

        await onDoneRenderingInAppMessage(givenNewMessageToShow, insideOfInlineView: view)

        // Expect that after done rendering, we display the new message.
        assert(view: view.messageRenderingLoadingView, isShowing: false, inInlineView: view)
        assert(view: view.inAppMessageView, isShowing: true, inInlineView: view)
        XCTAssertEqual(getInAppMessage(forView: view)?.templateId, givenNewMessageToShow.templateId)
    }

    @MainActor
    func test_showAnotherMessageAction_givenCloseNewMessage_expectShowNextMessageInQueue() async {
        let givenElementId = String.random
        let givenMessage = Message(elementId: givenElementId)
        let givenNextMessageInQueue = Message(elementId: givenElementId)
        await simulateSdkFetchedMessages([givenMessage, givenNextMessageInQueue], verifyInlineViewNotifiedOfFetch: nil)

        let view = InAppMessageView(elementId: givenElementId)

        await onDoneRenderingInAppMessage(givenMessage, insideOfInlineView: view)

        // Click the "Show next action" button on the currently displayed message.
        let givenNewMessageToShow = Message(templateId: .random)
        await onShowAnotherMessageActionButtonPressed(onInlineView: view, newMessageTemplateId: givenNewMessageToShow.templateId)
        await onDoneRenderingInAppMessage(givenNewMessageToShow, insideOfInlineView: view)

        // We expect that when we click the close action button on the new message that is being shown, we do not show the first message again. Instead, we expect to show the next message in the local queue.
        await onCloseActionButtonPressed(onInlineView: view)
        XCTAssertEqual(getInAppMessage(forView: view), givenNextMessageInQueue)
    }

    @MainActor
    func test_showAnotherMessageAction_givenShowingNewMessage_givenNewMessagesFetched_expectContinueShowingMessage() async {
        let givenMessage = Message.randomInline
        await simulateSdkFetchedMessages([givenMessage], verifyInlineViewNotifiedOfFetch: nil)

        let view = InAppMessageView(elementId: givenMessage.elementId!)

        await onDoneRenderingInAppMessage(givenMessage, insideOfInlineView: view)

        // Click the "Show next action" button on the currently displayed message.
        let givenNewMessageToShow = Message(templateId: .random)
        await onShowAnotherMessageActionButtonPressed(onInlineView: view, newMessageTemplateId: givenNewMessageToShow.templateId)
        await onDoneRenderingInAppMessage(givenNewMessageToShow, insideOfInlineView: view)

        // Expect that after a fetch, we do not change what message is being displayed.
        XCTAssertEqual(getInAppMessage(forView: view)?.templateId, givenNewMessageToShow.templateId)
        await simulateSdkFetchedMessages([Message.randomInline], verifyInlineViewNotifiedOfFetch: view)
        XCTAssertEqual(getInAppMessage(forView: view)?.templateId, givenNewMessageToShow.templateId)
    }

    @MainActor
    func test_showAnotherMessageAction_givenMultipleShowAnotherMessageActions_expectShowNextMessages() async {
        let givenMessage = Message.randomInline
        await simulateSdkFetchedMessages([givenMessage], verifyInlineViewNotifiedOfFetch: nil)

        let view = InAppMessageView(elementId: givenMessage.elementId!)

        await onDoneRenderingInAppMessage(givenMessage, insideOfInlineView: view)

        // Click the "Show next action" button on the currently displayed message.
        let givenNewMessageToShow = Message(templateId: .random)
        await onShowAnotherMessageActionButtonPressed(onInlineView: view, newMessageTemplateId: givenNewMessageToShow.templateId)
        await onDoneRenderingInAppMessage(givenNewMessageToShow, insideOfInlineView: view)
        XCTAssertEqual(getInAppMessage(forView: view)?.templateId, givenNewMessageToShow.templateId)

        // Click the "Show next action" button on the message we are currently displaying
        let given2ndNewMessageToShow = Message(templateId: .random)
        await onShowAnotherMessageActionButtonPressed(onInlineView: view, newMessageTemplateId: given2ndNewMessageToShow.templateId)
        await onDoneRenderingInAppMessage(given2ndNewMessageToShow, insideOfInlineView: view)
        XCTAssertEqual(getInAppMessage(forView: view)?.templateId, given2ndNewMessageToShow.templateId)
    }

    // MARK: - Deeplinks

    @MainActor
    func test_deeplinks_givenButtonTappedWithValidDeeplink_expectOpenDeeplink() async {
        let givenInlineMessage = Message.randomInline
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        XCTAssertTrue(isInlineViewVisible(inlineView))
        onDeepLinkActionButtonPressed(onInlineView: inlineView, deeplink: "https://customer.io")

        // Since a system call, hence no delegate is called
        XCTAssertFalse(inlineMessageDelegateMock.onActionClickCalled)

        // Do not dismiss inline message when deep link is opened
        XCTAssertTrue(isInlineViewVisible(inlineView))

        // If url is valid, check if `handleDeepLink` method is called
        XCTAssertTrue(deeplinkUtilMock.handleDeepLinkCalled)
        XCTAssertEqual(deeplinkUtilMock.handleDeepLinkReceivedArguments?.absoluteString, "https://customer.io")
    }

    @MainActor
    func test_deeplinks_givenButtonTappedWithInValidDeeplink_expectOpenDeeplink() async {
        let givenInlineMessage = Message.randomInline
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        XCTAssertTrue(isInlineViewVisible(inlineView))
        onDeepLinkActionButtonPressed(onInlineView: inlineView, deeplink: "ht!tp://invalid-url")

        // Since a system call, hence no delegate is called
        XCTAssertFalse(inlineMessageDelegateMock.onActionClickCalled)

        // Do not dismiss inline message when deep link is opened
        XCTAssertTrue(isInlineViewVisible(inlineView))

        // If url is valid, check if `handleDeepLink` method is called
        XCTAssertFalse(deeplinkUtilMock.handleDeepLinkCalled)
    }

    // MARK: persistent and non-persistent

    @MainActor
    func test_persistentAndNonPersistent_givenNonPersistentMessage_givenMessageShown_expectMessageNotShownAgain() async {
        let givenInlineMessage = Message(elementId: .random, persistent: false)
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        XCTAssertEqual(getInAppMessage(forView: inlineView), givenInlineMessage)
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        // Expect that when a new inline View is being constructed, it does not show the non-persistent message that has already been shown.
        let differentView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        XCTAssertNil(getInAppMessage(forView: differentView))
    }

    @MainActor
    func test_persistentAndNonPersistent_givenNonPersistentMessage_givenMessageNotYetShown_expectCanDisplayMessageMultipleTimes() async {
        let givenInlineMessage = Message(elementId: .random, persistent: false)
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        XCTAssertEqual(getInAppMessage(forView: inlineView), givenInlineMessage)

        // Expect that when a new inline View is being constructed, it shows the same non-persistent message that has not been shown yet.
        let differentView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        XCTAssertEqual(getInAppMessage(forView: differentView), givenInlineMessage)
    }

    @MainActor
    func test_persistentAndNonPersistent_givenPersistentMessage_givenMessageShown_expectMessageShownAgain() async {
        let givenInlineMessage = Message(elementId: .random, persistent: true)
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        XCTAssertEqual(getInAppMessage(forView: inlineView), givenInlineMessage)
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        // Expect that when a new inline View is being constructed, it shows the persistent message that has already been shown.
        let differentView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        XCTAssertEqual(getInAppMessage(forView: differentView), givenInlineMessage)
    }

    @MainActor
    func test_persistentAndNonPersistent_givenPersistentMessage_givenCloseMessage_expectDoNotShowMessageAgain() async {
        let givenInlineMessage = Message(elementId: .random, persistent: true)
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        XCTAssertEqual(getInAppMessage(forView: inlineView), givenInlineMessage)
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        // Expect that when the close button is tapped, the message is no longer shown
        await onCloseActionButtonPressed(onInlineView: inlineView)

        // Expect that when a new inline View is being constructed, it does not show the persistent message that has already been shown.
        let differentView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        XCTAssertNil(getInAppMessage(forView: differentView))
    }

    @MainActor
    func test_persistentAndNonPersistent_givenPersistentMessage_givenMessageExpires_expectContinueShowingIfAlreadyDisplayed_expectDoNotShowAgainInFuture() async {
        let givenInlineMessage = Message(elementId: .random, persistent: true)
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        XCTAssertEqual(getInAppMessage(forView: inlineView), givenInlineMessage)
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        // Expire the message
        await simulateSdkFetchedMessages([], verifyInlineViewNotifiedOfFetch: inlineView)

        // We expect to continue displaying the expired message on inline View that already displayed it
        XCTAssertEqual(getInAppMessage(forView: inlineView), givenInlineMessage)

        // Expect we will not show the message again in the future
        let differentView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        XCTAssertNil(getInAppMessage(forView: differentView))
    }

    // MARK: - Send events to Gist event listeners

    @MainActor
    func test_eventListener_givenErrorWithMessage_expectCallEventListener() async {
        let givenInlineMessage = Message.randomInline
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        await onDoneRenderingInAppMessageWithError(givenInlineMessage, insideOfInlineView: inlineView)

        assert(message: givenInlineMessage, didCallErrorWithMessageEventListener: true)
        assert(message: givenInlineMessage, didCallMessageShownEventListener: false)
        assert(message: givenInlineMessage, didCallMessageDismissedEventListener: false)
        assert(message: givenInlineMessage, didCallMessageActionTakenEventListener: false)
    }

    @MainActor
    func test_eventListener_givenMessageRendered_expectCallEventListener() async {
        let givenInlineMessage = Message.randomInline
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)

        // Expect do not call event listener yet
        assert(message: givenInlineMessage, didCallMessageShownEventListener: false)
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        // Expect to call listener after message rendered.
        assert(message: givenInlineMessage, didCallMessageShownEventListener: true)

        // Expect to not call the other event listeners
        assert(message: givenInlineMessage, didCallErrorWithMessageEventListener: false)
        assert(message: givenInlineMessage, didCallMessageDismissedEventListener: false)
        assert(message: givenInlineMessage, didCallMessageActionTakenEventListener: false)
    }

    @MainActor
    func test_eventListener_givenShowPersistentMessage_expectCallEventListener() async {
        let givenInlineMessage = Message(elementId: .random, persistent: true)
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        assert(message: givenInlineMessage, didCallMessageShownEventListener: true)
        assert(message: givenInlineMessage, didCallErrorWithMessageEventListener: false)
        assert(message: givenInlineMessage, didCallMessageDismissedEventListener: false)
        assert(message: givenInlineMessage, didCallMessageActionTakenEventListener: false)

        await onCloseActionButtonPressed(onInlineView: inlineView)

        assert(message: givenInlineMessage, didCallMessageDismissedEventListener: false)
        assert(message: givenInlineMessage, didCallMessageActionTakenEventListener: true)
    }

    @MainActor
    func test_eventListener_givenTapCloseButton_expectCallEventListener() async {
        let givenInlineMessage = Message.randomInline
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        assert(message: givenInlineMessage, didCallMessageActionTakenEventListener: false)

        await onCloseActionButtonPressed(onInlineView: inlineView)

        assert(message: givenInlineMessage, didCallMessageActionTakenEventListener: true)

        // Expect to never call message dismissed. Even with inline View not visible anymore after closing.
        assert(message: givenInlineMessage, didCallMessageDismissedEventListener: false)
    }

    @MainActor
    func test_eventListener_givenShowNextMessageInQueue_expectCallEventListener() async {
        let givenElementId = String.random
        let givenInlineMessage1 = Message(elementId: givenElementId)
        let givenInlineMessage2 = Message(elementId: givenElementId)
        await simulateSdkFetchedMessages([givenInlineMessage1, givenInlineMessage2], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenElementId)
        await onDoneRenderingInAppMessage(givenInlineMessage1, insideOfInlineView: inlineView)

        assert(message: givenInlineMessage1, didCallMessageShownEventListener: true)

        await onCloseActionButtonPressed(onInlineView: inlineView)
        await onDoneRenderingInAppMessage(givenInlineMessage2, insideOfInlineView: inlineView)

        assert(message: givenInlineMessage1, didCallMessageActionTakenEventListener: true)
        assert(message: givenInlineMessage1, didCallMessageShownEventListener: true)
        assert(message: givenInlineMessage2, didCallMessageShownEventListener: true)
    }

    @MainActor
    func test_eventListener_givenTapCustomActionButton_expectCallEventListener() async {
        let givenInlineMessage = Message.randomInline
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        assert(message: givenInlineMessage, didCallMessageActionTakenEventListener: false)

        await onCustomActionButtonPressed(onInlineView: inlineView)

        assert(message: givenInlineMessage, didCallMessageActionTakenEventListener: true)
    }

    @MainActor
    func test_eventListener_givenTapDeepLinkButton_expectCallEventListener() async {
        let givenInlineMessage = Message.randomInline
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        assert(message: givenInlineMessage, didCallMessageActionTakenEventListener: false)

        onDeepLinkActionButtonPressed(onInlineView: inlineView, deeplink: "https://customer.io/mobile")

        assert(message: givenInlineMessage, didCallMessageActionTakenEventListener: true)
    }

    @MainActor
    func test_eventListener_givenTapShowAnotherActionButton_expectCallEventListener() async {
        let givenInlineMessage = Message.randomInline
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        assert(message: givenInlineMessage, didCallMessageActionTakenEventListener: false)

        await onShowAnotherMessageActionButtonPressed(onInlineView: inlineView)

        // We expect to only call event listener once for the message.
        assert(message: givenInlineMessage, didCallMessageShownEventListener: true, expectedNumberOfEvents: 1)

        assert(message: givenInlineMessage, didCallMessageActionTakenEventListener: true)
    }

    // MARK: - Track open

    @MainActor
    func test_onInlineMessageRenderingNotShown_expectShouldNotTrackOpenedMetric() async {
        let givenInlineMessage = Message.randomInline
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        _ = InAppMessageView(elementId: givenInlineMessage.elementId!)

        assert(message: givenInlineMessage, didTrack: false, metric: "opened")
    }

    @MainActor
    func test_onInlineMessageShown_expectTrackOpenedMetric() async {
        let givenInlineMessage = Message.randomInline
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        assert(message: givenInlineMessage, didTrack: true, metric: "opened")
    }

    // MARK: - Track click

    @MainActor
    func test_onInlineMessageShown_onButtonTap_expectTrackClickedMetric() async {
        let givenInlineMessage = Message.randomInline
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        assert(message: givenInlineMessage, didTrack: false, metric: "clicked")
        await onCustomActionButtonPressed(onInlineView: inlineView)
        assert(message: givenInlineMessage, didTrack: true, metric: "clicked")
    }

    @MainActor
    func test_onInlineMessageShown_onMultipleButtonTap_expectMultipleTrackClickedMetric() async {
        let givenInlineMessage = Message.randomInline
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        assert(message: givenInlineMessage, didTrack: false, metric: "clicked")
        await onCustomActionButtonPressed(onInlineView: inlineView)
        assert(message: givenInlineMessage, didTrack: true, metric: "clicked")

        // Tap the button again and verify that we tracked another event
        await onCustomActionButtonPressed(onInlineView: inlineView)
        assert(message: givenInlineMessage, didTrack: true, metric: "clicked", expectedNumberOfEvents: 2)
    }

    // MARK: global event listener

    @MainActor
    func test_onInlineMessageShown_expectGlobalMessageShownListener() async {
        let givenInlineMessage = Message.randomInline
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        assert(message: givenInlineMessage, didCallMessageShownEventListener: true)
    }

    // Tests a scenario where multiple inline messages are displayed to the user,
    // then expect multiple MessageShown global event listeners to be called for each message shown.
    @MainActor
    func test_givenMultipleInlineMessageRendered_expectTrackMultipleMessageShownListenerCalls() async {
        let givenInlineMessage1 = Message.randomInline
        let givenInlineMessage2 = Message.randomInline
        await simulateSdkFetchedMessages([givenInlineMessage1, givenInlineMessage2], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView1 = InAppMessageView(elementId: givenInlineMessage1.elementId!)
        let inlineView2 = InAppMessageView(elementId: givenInlineMessage2.elementId!)

        await onDoneRenderingInAppMessage(givenInlineMessage1, insideOfInlineView: inlineView1)

        assert(message: givenInlineMessage1, didCallMessageShownEventListener: true)
        assert(message: givenInlineMessage2, didCallMessageShownEventListener: false)

        await onDoneRenderingInAppMessage(givenInlineMessage2, insideOfInlineView: inlineView2)

        assert(message: givenInlineMessage1, didCallMessageShownEventListener: true)
        assert(message: givenInlineMessage2, didCallMessageShownEventListener: true)
    }
}

@MainActor
extension InAppMessageViewTest {
    func setupQueueMock() -> MessageQueueManagerMock {
        let mock = MessageQueueManagerMock()

        diGraphShared.override(value: mock, forType: MessageQueueManager.self)

        return mock
    }

    // Only tells you if the View is visible in the UI to the user. Does not tell you if the View is in the process of rendering a message.
    func isInlineViewVisible(_ view: InAppMessageView) -> Bool {
        guard let viewHeightConstraint = view.heightConstraint else {
            return false
        }

        return viewHeightConstraint.constant > 0
    }

    // Tells you the message the Inline View is either rendering or has already rendered.
    func getInAppMessage(forView view: InAppMessageView) -> Message? {
        (view.inAppMessageView as? GistView)?.message
    }

    func assert(view: UIView?, isShowing: Bool, inInlineView inlineView: InAppMessageView, file: StaticString = #file, line: UInt = #line) {
        if isShowing {
            guard let view = view else {
                XCTFail("View is nil, therefore it is not showing", file: file, line: line)
                return
            }

            if view.isHidden {
                XCTFail("View is hidden, therefore it is not showing", file: file, line: line)
                return // it's hidden which is enough proof that it's not showing.
            }

            if !inlineView.subviews.contains(view) {
                XCTFail("View is not a subview of the inline view, therefore it is not showing", file: file, line: line)
            }
        } else { // is not showing
            guard let view = view else {
                // if View is nil, then it's not showing.
                return
            }

            if view.isHidden {
                return // it's hidden which is enough proof that it's not showing
            }

            if !inlineView.subviews.contains(view) {
                return // it's a subview of the inline view which means it's showing
            }

            XCTFail("View \(String(describing: view)) is showing inside of \(String(describing: inlineView))", file: file, line: line)
        }
    }

    func assert(message: Message, didTrack: Bool, metric: String, expectedNumberOfEvents: Int = 1, file: StaticString = #file, line: UInt = #line) {
        let foundMetrics = eventBusMetricsTracked.filter { $0.event == metric && $0.deliveryID == message.deliveryId }

        if didTrack {
            XCTAssertEqual(foundMetrics.count, expectedNumberOfEvents, "Expected to find metric \(metric) \(expectedNumberOfEvents) number of times, but it was tracked \(foundMetrics.count) many times", file: file, line: line)
        } else {
            XCTAssertTrue(foundMetrics.isEmpty, "Expected not to find metric \(metric) but it was tracked.", file: file, line: line)
        }
    }

    func assert(message: Message, didCallMessageShownEventListener: Bool, expectedNumberOfEvents: Int = 1, file: StaticString = #file, line: UInt = #line) {
        let foundEvents = eventListenerMock.messageShownReceivedInvocations.filter { $0.deliveryId == message.deliveryId }

        if didCallMessageShownEventListener {
            XCTAssertEqual(foundEvents.count, expectedNumberOfEvents, "Expected messageShown listener called \(expectedNumberOfEvents) number of times, but it was called \(foundEvents.count) many times", file: file, line: line)
        } else {
            XCTAssertTrue(foundEvents.isEmpty, "Expected not to find messageShown listener called, but it was.", file: file, line: line)
        }
    }

    func assert(message: Message, didCallMessageActionTakenEventListener: Bool, expectedNumberOfEvents: Int = 1, file: StaticString = #file, line: UInt = #line) {
        let foundEvents = eventListenerMock.messageActionTakenReceivedInvocations.filter { actualMessage, _, _ in actualMessage.deliveryId == message.deliveryId }

        if didCallMessageActionTakenEventListener {
            XCTAssertEqual(foundEvents.count, expectedNumberOfEvents, "Expected messageActionTaken listener called \(expectedNumberOfEvents) number of times, but it was called \(foundEvents.count) many times", file: file, line: line)
        } else {
            XCTAssertTrue(foundEvents.isEmpty, "Expected not to find messageActionTaken listener called, but it was.", file: file, line: line)
        }
    }

    func assert(message: Message, didCallMessageDismissedEventListener: Bool, expectedNumberOfEvents: Int = 1, file: StaticString = #file, line: UInt = #line) {
        let foundEvents = eventListenerMock.messageDismissedReceivedInvocations.filter { $0.deliveryId == message.deliveryId }

        if didCallMessageDismissedEventListener {
            XCTAssertEqual(foundEvents.count, expectedNumberOfEvents, "Expected messageDismissed listener called \(expectedNumberOfEvents) number of times, but it was called \(foundEvents.count) many times", file: file, line: line)
        } else {
            XCTAssertTrue(foundEvents.isEmpty, "Expected not to find messageDismissed listener called, but it was.", file: file, line: line)
        }
    }

    func assert(message: Message, didCallErrorWithMessageEventListener: Bool, expectedNumberOfEvents: Int = 1, file: StaticString = #file, line: UInt = #line) {
        let foundEvents = eventListenerMock.errorWithMessageReceivedInvocations.filter { $0.deliveryId == message.deliveryId }

        if didCallErrorWithMessageEventListener {
            XCTAssertEqual(foundEvents.count, expectedNumberOfEvents, "Expected errorWithMessage listener called \(expectedNumberOfEvents) number of times, but it was called \(foundEvents.count) many times", file: file, line: line)
        } else {
            XCTAssertTrue(foundEvents.isEmpty, "Expected not to find errorWithMessage listener called, but it was.", file: file, line: line)
        }
    }
}
