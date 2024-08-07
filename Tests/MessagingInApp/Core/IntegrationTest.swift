@testable import CioInternalCommon
@testable import CioMessagingInApp
import Foundation
@testable import SharedTests
import XCTest

/// Extension of `UnitTest` but performs some tasks that sets the environment for integration tests.
/// Unit test classes should have a predictable environment for easier debugging. Integration tests
/// have more SDK code involved and may require some modification to the test environment before tests run.
open class IntegrationTest: UnitTest {
    // Use minimal mocks/stubs in integration tests to closely match production behavior.

    // Mock HTTP requests to Gist backend services.
    let gistQueueNetworkMock = GistQueueNetworkMock()

    private var engineProvider: EngineWebProviderStub!

    override open func setUp() {
        super.setUp()

        engineProvider = EngineWebProviderStub()

        diGraphShared.override(value: engineProvider, forType: EngineWebProvider.self)
        diGraphShared.override(value: gistQueueNetworkMock, forType: GistQueueNetwork.self)
    }

    override open func initializeSDKComponents() -> MessagingInAppInstance? {
        // Initialize and configure MessagingPush for testing to closely resemble actual app setup
        MessagingInApp.setUpSharedInstanceForIntegrationTest(diGraphShared: diGraphShared, config: messagingInAppConfigOptions)

        return MessagingInApp.shared
    }

    func setupHttpResponse(code: Int, body: Data) {
        gistQueueNetworkMock.requestClosure = { _, _, _, _, completionHandler in
            let response = HTTPURLResponse(url: URL(string: "https://test.com")!, statusCode: code, httpVersion: nil, headerFields: nil)!

            completionHandler(.success((body, response)))
        }
    }

    // Given a list of messages, this function sets up a HTTP response for the fetch user queue request.
    func setupMockFetchResponse(messagesFetched messages: [Message]) {
        if messages.isEmpty {
            setupHttpResponse(code: 200, body: "[]".data)
            return
        }

        // Construct a JSON string that will become the HTTP response body.
        // The format of the JSON is the same as what /api/v1/users endpoint returns from Gist backend.
        //
        // We are opting to construct JSON strings manually with a dictionary because the data types used for parsing HTTP response bodies, `UserQueueResponse`, is not easily able to inherit the `Codable` protocol because of `[String: Any]`.
        //

        /* Example JSON string to modal the dictionary off of:
         [
           {
             "queueId": "e972deff-caa5-4b4c-be22-824fe323781d",
             "messageId": "levi-load-page-button",
             "priority": 5,
             "properties": {
               "gist": {
                 "position": "center",
                 "campaignId": "delivery-id-here",
                 "elementId": "inline-element-id-here",
                 "routeRuleAndroid": "^DO_NOT_DISPLAY_IN_APP$",
                 "routeRuleApple": "^(.*Dashboard.*)$",
                 "routeRuleWeb": "^DO_NOT_DISPLAY_IN_APP$"
               },
               "name": "okFNkDksSc@customer.io"
             }
           }
         ]
         */

        var jsonResponseArray: [[String: Any]] = []

        for message in messages {
            var gistProperties: [String: Any] = ["elementId": message.elementId!]

            if let campaignIdValue = message.gistProperties.campaignId {
                gistProperties["campaignId"] = campaignIdValue
            }
            if let persistentValue = message.gistProperties.persistent {
                gistProperties["persistent"] = persistentValue
            }

            let messageDict: [String: Any] = [
                "queueId": message.id!,
                "messageId": message.templateId,
                "priority": message.priority ?? 0,
                "properties": [
                    "gist": gistProperties
                ]
            ]

            jsonResponseArray.append(messageDict)
        }

        let jsonData = jsonAdapter.fromDictionary(jsonResponseArray)!

        setupHttpResponse(code: 200, body: jsonData)
    }
}

// MARK: utility functions for inline views

@MainActor
extension IntegrationTest {
    // When testing inline Views, simulate a fetch of messages from Gist backend.
    // Given list of messages to return from fetch request, the function will return after the inline View has been notified about this fetch and has processed it.
    func simulateSdkFetchedMessages(_ messages: [Message], verifyInlineViewNotifiedOfFetch inlineView: InlineMessageUIView?) async {
        let expectRefreshViewToBeCalled = expectation(description: "refreshViewToBeCalled")
        expectRefreshViewToBeCalled.assertForOverFulfill = false

        if let inlineView = inlineView?.inAppMessageView {
            inlineView.refreshViewListener = {
                expectRefreshViewToBeCalled.fulfill()
            }
        } else {
            expectRefreshViewToBeCalled.fulfill()
        }

        setupMockFetchResponse(messagesFetched: messages)

        // Now that the mock is setup, tell the SDK to perform the fetch HTTP request
        // swiftlint:disable:next force_cast
        (diGraphShared.messageQueueManager as! MessageQueueManagerImpl).fetchUserMessages()

        await fulfillment(of: [expectRefreshViewToBeCalled], timeout: 0.5)

        inlineView?.inAppMessageView?.refreshViewListener = nil
    }

    func onCloseActionButtonPressed(onInlineView inlineView: InlineMessageUIView) async {
        // Triggering the close button from the web engine simulates the user tapping the close button on the in-app WebView.
        // This behaves more like an integration test because we are also able to test the message manager, too.
        getWebEngineForInlineView(inlineView)?.delegate?.tap(name: "", action: GistMessageActions.close.rawValue, system: false)

        // When onCloseAction() is called on the inline View, it adds a task to the main thread queue. Our test wants to wait until this task is done running.
        await waitForMainThreadToFinishPendingTasks()
    }

    // Call when the in-app webview rendering process has finished.
    func onDoneRenderingInAppMessage(_ message: Message, insideOfInlineView inlineView: InlineMessageUIView, heightOfRenderedMessage: CGFloat = 100, widthOfRenderedMessage: CGFloat = 100) async {
        // The engine is like a HTTP layer in that it calls the Gist web server to get back rendered in-app messages.
        // To mock the web server call with a successful response back, call these delegate functions:
        getWebEngineForInlineView(inlineView)?.delegate?.routeLoaded(route: message.templateId)
        getWebEngineForInlineView(inlineView)?.delegate?.sizeChanged(width: widthOfRenderedMessage, height: heightOfRenderedMessage)

        await waitForEventBusEventsToPost()
        // When sizeChanged() is called on the inline View, it adds a task to the main thread queue. Our test wants to wait until this task is done running.
        await waitForMainThreadToFinishPendingTasks()
    }

    func onShowAnotherMessageActionButtonPressed(onInlineView inlineView: InlineMessageUIView, newMessageTemplateId: String = .random) async {
        // Triggering the button from the web engine simulates the user tapping the button on the in-app WebView.
        // This behaves more like an integration test because we are also able to test the message manager, too.
        getWebEngineForInlineView(inlineView)?.delegate?.tap(name: "", action: "engine://router-change-route/\(newMessageTemplateId)", system: false)
        getWebEngineForInlineView(inlineView)?.delegate?.routeChanged(newRoute: newMessageTemplateId)

        // When willChangeMessage() is called on the inline View, it adds a task to the main thread queue. Our test wants to wait until this task is done running.
        await waitForMainThreadToFinishPendingTasks()
    }

    func getWebEngineForInlineView(_ view: InlineMessageUIView) -> EngineWebInstance? {
        view.inAppMessageView?.inlineMessageManager?.engine
    }
}

// MARK: utility functions for modal views

@MainActor
extension IntegrationTest {
    func onCustomActionButtonPressed(onInlineView inlineView: InlineMessageUIView) async {
        // Triggering the custom action button on inline message from the web engine
        // mocks the user tap on custom action button
        getWebEngineForInlineView(inlineView)?.delegate?.tap(name: "", action: "Test", system: false)

        // when a button is pressed, an eventbus event is posted for metrics tracking. Return function after the tracked event is posted.
        await waitForEventBusEventsToPost()
    }

    func onDeepLinkActionButtonPressed(onInlineView inlineView: InlineMessageUIView, deeplink: String) {
        // Triggering the custom action button on inline message from the web engine
        // mocks the user tap on custom action button
        getWebEngineForInlineView(inlineView)?.delegate?.tap(name: "", action: deeplink, system: true)
    }

    func onCloseActionButtonPressedOnModal() async {
        // Triggering the close button from the web engine simulates the user tapping the close button on the in-app WebView.
        // This behaves more like an integration test because we are also able to test the message manager, too.
        getWebEngineForModalView()?.delegate?.tap(name: "", action: GistMessageActions.close.rawValue, system: false)

        // When onCloseAction() is called on the inline View, it adds a task to the main thread queue. Our test wants to wait until this task is done running.
        await waitForMainThreadToFinishPendingTasks()
    }

    // Call when the in-app webview rendering process has finished.
    func onDoneRenderingInAppMessageOnModal(_ message: Message, heightOfRenderedMessage: CGFloat = 100, widthOfRenderedMessage: CGFloat = 100) async {
        // The engine is like a HTTP layer in that it calls the Gist web server to get back rendered in-app messages.
        // To mock the web server call with a successful response back, call these delegate functions:
        getWebEngineForModalView()?.delegate?.routeLoaded(route: message.templateId)
        getWebEngineForModalView()?.delegate?.sizeChanged(width: widthOfRenderedMessage, height: heightOfRenderedMessage)

        // When sizeChanged() is called on the inline View, it adds a task to the main thread queue. Our test wants to wait until this task is done running.
        await waitForMainThreadToFinishPendingTasks()
    }

    func getWebEngineForModalView() -> EngineWebInstance? {
        Gist.shared.getModalMessageManager()?.engine
    }
}
