@testable import CioInternalCommon
@testable import CioMessagingInApp
import Foundation
import SharedTests
import XCTest

class InAppMessageViewTest: IntegrationTest {
    private let engineWebMock = EngineWebInstanceMock()
    private let inlineMessageDelegateMock = InAppMessageViewActionDelegateMock()
    private var engineProvider: EngineWebProviderStub2!
    private let eventListenerMock = InAppEventListenerMock()
    private let deeplinkUtilMock = DeepLinkUtilMock()

    override func setUp() {
        super.setUp()

        // Set a random user token so that the SDK can perform fetches for user messages.
        UserManager().setUserToken(userToken: .random)

        DIGraphShared.shared.override(value: deeplinkUtilMock, forType: DeepLinkUtil.self)
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

        let webViewBeforeFetch = getInAppMessageWebView(fromInlineView: inlineView)

        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: inlineView)

        let webViewAfterFetch = getInAppMessageWebView(fromInlineView: inlineView)

        // If the WebViews are the same instance, it means the message was not reloaded.
        XCTAssertTrue(webViewBeforeFetch === webViewAfterFetch)
    }

    @MainActor
    func test_givenAlreadyShowingInAppMessage_whenNewMessageFetched_expectDoNotReplaceContents() async {
        let givenOldInlineMessage = Message.randomInline
        await simulateSdkFetchedMessages([givenOldInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenOldInlineMessage.elementId!)
        let webViewBeforeFetch = getInAppMessageWebView(fromInlineView: inlineView)

        // Make sure message is a new message, but has same elementId.
        let givenNewInlineMessage = Message(queueId: .random, elementId: givenOldInlineMessage.elementId)

        await simulateSdkFetchedMessages([givenNewInlineMessage], verifyInlineViewNotifiedOfFetch: inlineView)

        let webViewAfterFetch = getInAppMessageWebView(fromInlineView: inlineView)

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

    // MARK: - onInlineButtonAction

    @MainActor
    func test_onInlineButtonAction_givenDelegateSet_expectCustomCallback() async {
        messagingInAppImplementation.setEventListener(eventListenerMock)

        let givenInlineMessage = Message.randomInline
        let gistInAppInlineMessage = InAppMessage(gistMessage: givenInlineMessage)
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

        let inlineView = InAppMessageView(elementId: givenInlineMessage.elementId!)
        inlineView.onActionDelegate = inlineMessageDelegateMock
        await onDoneRenderingInAppMessage(givenInlineMessage, insideOfInlineView: inlineView)

        XCTAssertTrue(isInlineViewVisible(inlineView))
        onCustomActionButtonPressed(onInlineView: inlineView)

        XCTAssertTrue(inlineMessageDelegateMock.onActionClickCalled)
        XCTAssertEqual(inlineMessageDelegateMock.onActionClickReceivedArguments?.message, gistInAppInlineMessage)
        XCTAssertEqual(inlineMessageDelegateMock.onActionClickReceivedArguments?.actionValue, "Test")
        XCTAssertEqual(inlineMessageDelegateMock.onActionClickReceivedArguments?.actionName, "")

        // FIXME: The global listener should not be called when the delegate is set.

        // Also check that the global listener is not called
        XCTAssertTrue(eventListenerMock.messageActionTakenCalled)
    }

    @MainActor
    func test_onInlineButtonAction_givenDelegateNotSet_expectGlobalCallback() async {
        messagingInAppImplementation.setEventListener(eventListenerMock)

        let givenInlineMessage = Message.randomInline
        let gistInAppInlineMessage = InAppMessage(gistMessage: givenInlineMessage)
        await simulateSdkFetchedMessages([givenInlineMessage], verifyInlineViewNotifiedOfFetch: nil)

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
        onCustomActionButtonPressed(onInlineView: inlineView1)

        // Check that only inlineActionDelegate1's delegate method is called
        XCTAssertFalse(inlineActionDelegate2.mockCalled)
        XCTAssertTrue(inlineActionDelegate1.onActionClickCalled)

        // Check that the button is called once and values received as parameters
        // match the view that triggered the button tap
        XCTAssertTrue(inlineActionDelegate1.onActionClickCalled)
        XCTAssertEqual(inlineActionDelegate1.onActionClickCallsCount, 1)

        // FIXME: The global listener should not be called when the delegate is set.
        XCTAssertTrue(eventListenerMock.messageActionTakenCalled)

        XCTAssertEqual(inlineActionDelegate1.onActionClickReceivedArguments?.message, gistInAppInlineMessage1)
        XCTAssertEqual(inlineActionDelegate1.onActionClickReceivedArguments?.actionValue, "Test")
        XCTAssertEqual(inlineActionDelegate1.onActionClickReceivedArguments?.actionName, "")
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
        getInAppMessageWebView(fromInlineView: view)?.message
    }

    func getInAppMessageWebView(fromInlineView view: InAppMessageView) -> GistView? {
        let gistViews: [GistView] = view.subviews.map { $0 as? GistView }.mapNonNil()

        if gistViews.isEmpty {
            return nil
        }

        XCTAssertEqual(gistViews.count, 1)

        return gistViews.first
    }
}
