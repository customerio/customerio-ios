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
}

// MARK: utility functions for inline views

@MainActor
extension IntegrationTest {
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

        await waitForEventBusEventsToPost()
        // When sizeChanged() is called on the inline View, it adds a task to the main thread queue. Our test wants to wait until this task is done running.
        await waitForMainThreadToFinishPendingTasks()
    }

    // Call when the in-app webview rendering process has finished with error
    func onDoneRenderingInAppMessageWithError(_ message: Message, insideOfInlineView inlineView: InAppMessageView) async {
        // To mock the web server call with a failed response back, call routeError delegate function:
        getWebEngineForInlineView(inlineView)?.delegate?.routeError(route: message.templateId)
    }

    func onShowAnotherMessageActionButtonPressed(onInlineView inlineView: InAppMessageView, newMessageTemplateId: String = .random) async {
        // Triggering the button from the web engine simulates the user tapping the button on the in-app WebView.
        // This behaves more like an integration test because we are also able to test the message manager, too.
        getWebEngineForInlineView(inlineView)?.delegate?.routeChanged(newRoute: newMessageTemplateId)

        // When willChangeMessage() is called on the inline View, it adds a task to the main thread queue. Our test wants to wait until this task is done running.
        await waitForMainThreadToFinishPendingTasks()
    }

    func getWebEngineForInlineView(_ view: InAppMessageView) -> EngineWebInstance? {
        view.inlineMessageManager?.engine
    }
}

// MARK: utility functions for modal views

@MainActor
extension IntegrationTest {
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
