@testable import CioInternalCommon
@testable import CioMessagingInApp
import Foundation
import SharedTests
import XCTest

class InAppMessageViewTest: IntegrationTest {
    private let queueMock = MessageQueueManagerMock()
    private let engineWebMock = EngineWebInstanceMock()
    private let inlineMessageDelegateMock = InAppMessageViewActionDelegateMock()
    private var engineProvider: EngineWebProviderStub2!
    private let eventListenerMock = InAppEventListenerMock()
    private let deeplinkUtilMock = DeepLinkUtilMock()
    private var eventBusHandlerMock = EventBusHandlerMock()
    override func setUp() {
        super.setUp()

        DIGraphShared.shared.override(value: queueMock, forType: MessageQueueManager.self)
        DIGraphShared.shared.override(value: deeplinkUtilMock, forType: DeepLinkUtil.self)
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
        assert(view: inlineView.inAppMessageView, isShowing: true, inInlineView: inlineView)
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
        assert(view: inlineView.inAppMessageView, isShowing: true, inInlineView: inlineView)
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
        assert(view: view.inAppMessageView, isShowing: true, inInlineView: view)
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

        let webViewBeforeFetch = inlineView.inAppMessageView

        await simulateSdkFetchedMessages([givenInlineMessage])

        let webViewAfterFetch = inlineView.inAppMessageView

        // If the WebViews are the same instance, it means the message was not reloaded.
        XCTAssertTrue(webViewBeforeFetch === webViewAfterFetch)
    }

    @MainActor
    func test_givenAlreadyShowingInAppMessage_whenNewMessageFetched_expectDoNotReplaceContents() async {
        let givenOldInlineMessage = Message.randomInline
        queueMock.getInlineMessagesReturnValue = [givenOldInlineMessage]

        let inlineView = InAppMessageView(elementId: givenOldInlineMessage.elementId!)
        let webViewBeforeFetch = inlineView.inAppMessageView

        // Make sure message is a new message, but has same elementId.
        let givenNewInlineMessage = Message(queueId: .random, elementId: givenOldInlineMessage.elementId)

        await simulateSdkFetchedMessages([givenNewInlineMessage])

        let webViewAfterFetch = inlineView.inAppMessageView

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

    @MainActor
    func test_expiration_givenExpiredMessageNotYetDisplayed_expectDoNotDisplayMessage() async {
        let givenMessageDisplayed = Message(elementId: .random)
        let givenMessageThatExpires = Message(elementId: .random)
        queueMock.getInlineMessagesReturnValue = [givenMessageDisplayed, givenMessageThatExpires]

        let inlineView = InAppMessageView(elementId: givenMessageDisplayed.elementId!)

        await onDoneRenderingInAppMessage(givenMessageDisplayed, insideOfInlineView: inlineView)

        XCTAssertTrue(isInlineViewVisible(inlineView))
        XCTAssertEqual(getInAppMessage(forView: inlineView), givenMessageDisplayed)

        // Simulate message expiration.
        await simulateSdkFetchedMessages([givenMessageDisplayed])

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
    func test_onCloseAction_givenMultipleMessagesInQueue_expectShowLoadingViewWhileRenderingNextMessage() async {
        let givenElementId = String.random
        let givenMessages = [Message(elementId: givenElementId), Message(elementId: givenElementId)]
        queueMock.getInlineMessagesReturnValue = givenMessages

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

    // MARK: - onInlineButtonAction

    @MainActor
    func test_onInlineButtonAction_givenDelegateSet_expectCustomCallback() async {
        messagingInAppImplementation.setEventListener(eventListenerMock)

        let givenInlineMessage = Message.randomInline
        let gistInAppInlineMessage = InAppMessage(gistMessage: givenInlineMessage)
        queueMock.getInlineMessagesReturnValue = [givenInlineMessage]

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        inlineView.onActionDelegate = inlineMessageDelegateMock
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        XCTAssertTrue(isInlineViewVisible(inlineView))
        onCustomActionButtonPressed(onInlineView: inlineView)

        XCTAssertTrue(inlineMessageDelegateMock.onActionClickCalled)
        XCTAssertEqual(inlineMessageDelegateMock.onActionClickReceivedArguments?.message, gistInAppInlineMessage)
        XCTAssertEqual(inlineMessageDelegateMock.onActionClickReceivedArguments?.actionValue, "Test")
        XCTAssertEqual(inlineMessageDelegateMock.onActionClickReceivedArguments?.actionName, "")

        // Also check that the global listener is not called
        XCTAssertFalse(eventListenerMock.messageActionTakenCalled)
    }

    @MainActor
    func test_onInlineButtonAction_givenDelegateNotSet_expectGlobalCallback() async {
        messagingInAppImplementation.setEventListener(eventListenerMock)

        let givenInlineMessage = Message.randomInline
        let gistInAppInlineMessage = InAppMessage(gistMessage: givenInlineMessage)
        queueMock.getInlineMessagesReturnValue = [givenInlineMessage]

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        XCTAssertTrue(isInlineViewVisible(inlineView))
        onCustomActionButtonPressed(onInlineView: inlineView)

        XCTAssertFalse(inlineMessageDelegateMock.onActionClickCalled)
        XCTAssertTrue(eventListenerMock.messageActionTakenCalled)
        XCTAssertEqual(eventListenerMock.messageActionTakenReceivedArguments?.message, gistInAppInlineMessage)
        XCTAssertEqual(eventListenerMock.messageActionTakenReceivedArguments?.actionValue, "Test")
        XCTAssertEqual(eventListenerMock.messageActionTakenReceivedArguments?.actionName, "")
    }

    @MainActor
    func test_onInlineButtonAction_multipleInlineMessages_givenDelegateSetForAll_expectSingleCustomCallback() async {
        messagingInAppImplementation.setEventListener(eventListenerMock)

        let givenInlineMessage1 = Message.randomInline
        let gistInAppInlineMessage1 = InAppMessage(gistMessage: givenInlineMessage1)

        let givenInlineMessage2 = Message.randomInline
        queueMock.getInlineMessagesReturnValue = [givenInlineMessage1, givenInlineMessage2]

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
        onCustomActionButtonPressed(onInlineView: inlineView1)

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
        queueMock.getInlineMessagesReturnValue = [givenMessage]

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
        queueMock.getInlineMessagesReturnValue = [givenMessage]

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
        let givenMessage = Message.randomInline
        let givenNextMessageInQueue = Message.randomInline
        queueMock.getInlineMessagesReturnValue = [givenMessage, givenNextMessageInQueue]

        let view = InAppMessageView(elementId: givenMessage.elementId!)

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
        queueMock.getInlineMessagesReturnValue = [givenMessage]

        let view = InAppMessageView(elementId: givenMessage.elementId!)

        await onDoneRenderingInAppMessage(givenMessage, insideOfInlineView: view)

        // Click the "Show next action" button on the currently displayed message.
        let givenNewMessageToShow = Message(templateId: .random)
        await onShowAnotherMessageActionButtonPressed(onInlineView: view, newMessageTemplateId: givenNewMessageToShow.templateId)
        await onDoneRenderingInAppMessage(givenNewMessageToShow, insideOfInlineView: view)

        // Expect that after a fetch, we do not change what message is being displayed.
        XCTAssertEqual(getInAppMessage(forView: view)?.templateId, givenNewMessageToShow.templateId)
        await simulateSdkFetchedMessages([Message.randomInline])
        XCTAssertEqual(getInAppMessage(forView: view)?.templateId, givenNewMessageToShow.templateId)
    }

    @MainActor
    func test_showAnotherMessageAction_givenMultipleShowAnotherMessageActions_expectShowNextMessages() async {
        let givenMessage = Message.randomInline
        queueMock.getInlineMessagesReturnValue = [givenMessage]

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
        queueMock.getInlineMessagesReturnValue = [givenInlineMessage]

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
        queueMock.getInlineMessagesReturnValue = [givenInlineMessage]

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

    // MARK: - Track open

    @MainActor
    func test_onInlineMessageShown_expectTrackOpenedMetric_expectGlobalMessageShownListener() async {
        let inlineView = await showInlineMessageForMetrics()

        XCTAssertTrue(isInlineViewVisible(inlineView))

        // Check if messageShown is called
        XCTAssertTrue(eventListenerMock.messageShownCalled)
        XCTAssertEqual(eventListenerMock.messageShownCallsCount, 1)

        // Also check for postEvent calls
        XCTAssertTrue(eventBusHandlerMock.postEventCalled)
        XCTAssertEqual(eventBusHandlerMock.postEventCallsCount, 1)
    }

    @MainActor
    func test_givenMultipleInlineMessageInQueue_BothDisplayedAndOneDismissed_expectTrackMultipleMessageShownListenerCalls() async {
        messagingInAppImplementation.setEventListener(eventListenerMock)
        messagingInAppImplementation.setEventBusHandler(eventBusHandlerMock)

        let givenInlineMessage1 = Message.randomInline
        let givenInlineMessage2 = Message.randomInline
        queueMock.getInlineMessagesReturnValue = [givenInlineMessage1, givenInlineMessage2]

        let inlineView1 = InAppMessageView(elementId: givenInlineMessage1.elementId!)
        let inlineView2 = InAppMessageView(elementId: givenInlineMessage2.elementId!)

        // Render only inlineView1
        await onDoneRenderingInAppMessage(givenInlineMessage1, insideOfInlineView: inlineView1)

        // inlineView1 is only visible
        XCTAssertTrue(isInlineViewVisible(inlineView1))
        XCTAssertFalse(isInlineViewVisible(inlineView2))

        // Check if messageShown is called
        XCTAssertTrue(eventListenerMock.messageShownCalled)
        XCTAssertEqual(eventListenerMock.messageShownCallsCount, 1)

        // Also check for postEvent calls
        XCTAssertTrue(eventBusHandlerMock.postEventCalled)
        XCTAssertEqual(eventBusHandlerMock.postEventCallsCount, 1)

        // Dismiss inlineView1 and show inlineView2
        await onCloseActionButtonPressed(onInlineView: inlineView1)
        await onDoneRenderingInAppMessage(givenInlineMessage2, insideOfInlineView: inlineView2)

        // Check messageShownCalled called again
        XCTAssertTrue(eventListenerMock.messageShownCalled)
        XCTAssertEqual(eventListenerMock.messageShownCallsCount, 2)

        // Also check for postEvent calls
        XCTAssertTrue(eventBusHandlerMock.postEventCalled)
        XCTAssertEqual(eventBusHandlerMock.postEventCallsCount, 2)
    }

    // MARK: - Track click

    @MainActor
    func test_onInlineMessageShown_givenDelegateNotSet_onSingleButtonTap_expectTrackClickedMetric_expectGlobalMessageActionTakenCallback() async {
        DIGraphShared.shared.override(value: eventBusHandlerMock, forType: EventBusHandler.self)
        let inlineView = await showInlineMessageForMetrics()
        XCTAssertTrue(isInlineViewVisible(inlineView))

        // Tap button once
        onCustomActionButtonPressed(onInlineView: inlineView)

        // Check if messageActionTaken is called
        XCTAssertTrue(eventListenerMock.messageActionTakenCalled)
        XCTAssertEqual(eventListenerMock.messageActionTakenCallsCount, 1)

        // Check other handlers are not called
        XCTAssertFalse(eventListenerMock.messageDismissedCalled)
        XCTAssertFalse(eventListenerMock.errorWithMessageCalled)

        // Also check for postEvent calls
        XCTAssertTrue(eventBusHandlerMock.postEventCalled)
        // The first post call occurs when the message is shown,
        // and the second post call is triggered by the button click action.
        XCTAssertEqual(eventBusHandlerMock.postEventCallsCount, 2)
    }

    @MainActor
    func test_onInlineMessageShown_givenDelegateNotSet_onMultipleButtonTap_expectGlobalMessageActionTakenCallback() async {
        DIGraphShared.shared.override(value: eventBusHandlerMock, forType: EventBusHandler.self)
        let inlineView = await showInlineMessageForMetrics()
        DIGraphShared.shared.override(value: eventBusHandlerMock, forType: EventBusHandler.self)
        XCTAssertTrue(isInlineViewVisible(inlineView))
        onCustomActionButtonPressed(onInlineView: inlineView)

        // Check if messageActionTaken is called
        XCTAssertTrue(eventListenerMock.messageActionTakenCalled)
        XCTAssertEqual(eventListenerMock.messageActionTakenCallsCount, 1)

        // Also check for postEvent calls
        XCTAssertTrue(eventBusHandlerMock.postEventCalled)
        // The first post call occurs when the message is shown,
        // and the second post call is triggered by the button click action.
        XCTAssertEqual(eventBusHandlerMock.postEventCallsCount, 2)

        // Check other listeners are not called except shown
        XCTAssertTrue(eventListenerMock.messageShownCalled)
        XCTAssertFalse(eventListenerMock.messageDismissedCalled)
        XCTAssertFalse(eventListenerMock.errorWithMessageCalled)

        // Tap button again
        onCustomActionButtonPressed(onInlineView: inlineView)
        XCTAssertEqual(eventListenerMock.messageActionTakenCallsCount, 2)
        // Tap the button again and verify that
        // the count of post calls to track metrics updates
        XCTAssertEqual(eventBusHandlerMock.postEventCallsCount, 3)
    }

    @MainActor
    func test_onInlineMessageShown_givenDelegateSet_onMultipleButtonTap_expectSingleTrackClickedMetric_expectGlobalMessageActionTakenCallback() async {
        DIGraphShared.shared.override(value: eventBusHandlerMock, forType: EventBusHandler.self)

        let inlineView = await showInlineMessageForMetrics(setDelegate: true)
        XCTAssertTrue(isInlineViewVisible(inlineView))
        onCustomActionButtonPressed(onInlineView: inlineView)

        XCTAssertTrue(inlineMessageDelegateMock.onActionClickCalled)
        XCTAssertEqual(inlineMessageDelegateMock.onActionClickCallsCount, 1)
        XCTAssertFalse(eventListenerMock.messageActionTakenCalled)
        XCTAssertEqual(eventBusHandlerMock.postEventCallsCount, 2)

        // Tap the button again and verify that
        // the call to onActionClick updates
        onCustomActionButtonPressed(onInlineView: inlineView)
        XCTAssertEqual(eventBusHandlerMock.postEventCallsCount, 3)
        XCTAssertEqual(inlineMessageDelegateMock.onActionClickCallsCount, 2)
    }

    @MainActor
    func showInlineMessageForMetrics(setDelegate: Bool = false) async -> InAppMessageView {
        messagingInAppImplementation.setEventListener(eventListenerMock)
        messagingInAppImplementation.setEventBusHandler(eventBusHandlerMock)

        let givenInlineMessage = Message.randomInline
        queueMock.getInlineMessagesReturnValue = [givenInlineMessage]

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        if setDelegate {
            inlineView.onActionDelegate = inlineMessageDelegateMock
        }
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        return inlineView
    }
}

@MainActor
extension InAppMessageViewTest {
    func onCustomActionButtonPressed(onInlineView inlineView: InAppMessageView) {
        // Triggering the custom action button on inline message from the web engine
        // mocks the user tap on custom action button
        getWebEngineForInlineView(inlineView)?.delegate?.tap(name: "", action: "Test", system: false)
    }

    func onDeepLinkActionButtonPressed(onInlineView inlineView: InAppMessageView, deeplink: String) {
        // Triggering the custom action button on inline message from the web engine
        // mocks the user tap on custom action button
        getWebEngineForInlineView(inlineView)?.delegate?.tap(name: "", action: deeplink, system: true)
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
