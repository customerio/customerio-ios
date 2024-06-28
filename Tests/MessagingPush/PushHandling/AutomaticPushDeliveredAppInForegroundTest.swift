@testable import CioInternalCommon
@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

// When a push is delivered to an iOS device and the app is in the foreground, iOS gives the app the option to either display that push or to not display that push.
class AutomaticPushDeliveredAppInForegrondTest: IntegrationTest {
    private var pushEventHandler: PushEventHandler!

    private let pushClickHandler = PushClickHandlerMock()
    private var pushEventHandlerProxy: PushEventHandlerProxy {
        DIGraphShared.shared.pushEventHandlerProxy
    }

    // MARK: SDK configuration behavior

    func test_givenCioPushDelivered_givenSdkConfigDisplayPush_expectPushDisplayed() {
        configureSdk(shouldDisplayPushAppInForeground: true)

        let givenPush = PushNotificationStub.getPushSentFromCIO()

        let didPushGetDisplayed = deliverPush(givenPush)

        XCTAssertEqual(didPushGetDisplayed, true)
    }

    func test_givenCioPushDelivered_givenSdkConfigDoNotDisplayPush_expectPushNotDisplayed() {
        configureSdk(shouldDisplayPushAppInForeground: false)

        let givenPush = PushNotificationStub.getPushSentFromCIO()

        let didPushGetDisplayed = deliverPush(givenPush)

        XCTAssertEqual(didPushGetDisplayed, false)
    }

    // MARK: cio SDK only push event handler in app

    func test_givenCioOnlyPushHandler_givenNonCioPushDelivered_expectHandleEvent() {
        configureSdk(shouldDisplayPushAppInForeground: true)

        let givenPush = PushNotificationStub.getPushNotSentFromCIO()

        let didPushGetDisplayed = deliverPush(givenPush)

        XCTAssertEqual(didPushGetDisplayed, true)
    }

    // MARK: multiple push handlers in app

    func test_givenOtherPushHandlers_givenNonCioPushDelivered_expectHandleEvent() {
        configureSdk(shouldDisplayPushAppInForeground: false)
        let givenPush = PushNotificationStub.getPushNotSentFromCIO()
        var otherPushHandlerCalled = false

        let givenOtherPushHandler = getNewPushEventHandler()
        givenOtherPushHandler.shouldDisplayPushAppInForegroundClosure = { _, onComplete in
            otherPushHandlerCalled = true

            onComplete(true)
        }
        addOtherPushEventHandler(givenOtherPushHandler)

        _ = deliverPush(givenPush)

        XCTAssertTrue(otherPushHandlerCalled)
    }

    func test_givenOtherPushHandlers_givenCioPushDelivered_expectOtherPushHandlerGetsCallback_expectIgnoreResultOfOtherHandler() {
        configureSdk(shouldDisplayPushAppInForeground: true)
        let givenPush = PushNotificationStub.getPushSentFromCIO()
        let expectOtherPushHandlerCallbackCalled = expectation(description: "Expect other push handler callback called")

        let givenOtherPushHandler = getNewPushEventHandler()
        givenOtherPushHandler.shouldDisplayPushAppInForegroundClosure = { _, onComplete in
            // We expect that other push handler gets callback of push event from CIO push
            expectOtherPushHandlerCallbackCalled.fulfill()

            // We expect that this return result is ignored. The CIO SDK config setting is used instead.
            onComplete(false)
        }
        addOtherPushEventHandler(givenOtherPushHandler)

        let didPushGetDisplayed = deliverPush(givenPush)

        waitForExpectations()

        // Check that the decision to display push was determined by SDK config and not from the return result of 3rd party callback.
        XCTAssertEqual(didPushGetDisplayed, true)
    }

    // Important to test that 2+ 3rd party push handlers for some use cases.
    func test_givenMultiplePushHandlers_givenCioPushDelivered_expectOtherPushHandlersGetCallback() {
        configureSdk(shouldDisplayPushAppInForeground: true)
        let givenPush = PushNotificationStub.getPushSentFromCIO()
        let expectOtherPushHandlerCallbackCalled = expectation(description: "Expect other push handler callback called")
        expectOtherPushHandlerCallbackCalled.expectedFulfillmentCount = 2

        let givenOtherPushHandler1 = getNewPushEventHandler()
        let givenOtherPushHandler2 = getNewPushEventHandler()
        givenOtherPushHandler1.shouldDisplayPushAppInForegroundClosure = { _, onComplete in
            expectOtherPushHandlerCallbackCalled.fulfill()

            onComplete(true)
        }
        givenOtherPushHandler2.shouldDisplayPushAppInForegroundClosure = { _, onComplete in
            expectOtherPushHandlerCallbackCalled.fulfill()

            onComplete(true)
        }
        addOtherPushEventHandler(givenOtherPushHandler1)
        addOtherPushEventHandler(givenOtherPushHandler2)

        _ = deliverPush(givenPush)

        waitForExpectations()
    }

    // MARK: completion handler

    func test_givenMultiplePushHandlers_givenCioPushDelivered_givenOtherPushHandlerDoesNotCallCompletionHandler_expectCompletionHandlerDoesNotGetCalled() {
        configureSdk(shouldDisplayPushAppInForeground: true)

        let expectOtherClickHandlerToGetCallback = expectation(description: "Receive a callback")
        let givenPush = PushNotificationStub.getPushSentFromCIO()
        let givenOtherPushHandler = getNewPushEventHandler()

        givenOtherPushHandler.shouldDisplayPushAppInForegroundClosure = { _, _ in
            // Do not call completion handler.
            expectOtherClickHandlerToGetCallback.fulfill()
        }
        addOtherPushEventHandler(givenOtherPushHandler)

        let didPushGetDisplayed = deliverPush(givenPush, expectToCallCompletionHandler: false)

        waitForExpectations(for: [expectOtherClickHandlerToGetCallback])

        // nil result means that completionHandler never got called and returned a result.
        XCTAssertNil(didPushGetDisplayed)
    }
}

extension AutomaticPushDeliveredAppInForegrondTest {
    private func configureSdk(shouldDisplayPushAppInForeground: Bool) {
        let pushModuleConfig = MessagingPushConfigBuilder()
            .showPushAppInForeground(shouldDisplayPushAppInForeground)
            .build()

        pushEventHandler = IOSPushEventListener(
            jsonAdapter: diGraphShared.jsonAdapter,
            pushEventHandlerProxy: pushEventHandlerProxy,
            moduleConfig: pushModuleConfig,
            pushClickHandler: pushClickHandler,
            pushHistory: diGraphShared.pushHistory,
            logger: diGraphShared.logger
        )
    }

    func deliverPush(_ push: PushNotification, expectToCallCompletionHandler: Bool = true) -> Bool? {
        // Note: It's important that we test that the `withContentHandler` callback function gets called either by our SDK (when we handle it), or the 3rd party handler.
        let expectCompletionHandlerCalled = expectation(description: "Expect completion handler called by a handler")
        if expectToCallCompletionHandler {
            expectCompletionHandlerCalled.expectedFulfillmentCount = 1 // Test will fail if called 2+ times which could indicate a bug because only 1 push click handler should be calling it.
        } else {
            expectCompletionHandlerCalled.isInverted = true
        }

        var returnValueFromPushHandler: Bool?

        pushEventHandler.shouldDisplayPushAppInForeground(push) { shouldDisplayPush in
            returnValueFromPushHandler = shouldDisplayPush

            expectCompletionHandlerCalled.fulfill()
        }

        waitForExpectations(for: [expectCompletionHandlerCalled])

        return returnValueFromPushHandler
    }

    func addOtherPushEventHandler(_ pushEventHandler: PushEventHandler) {
        pushEventHandlerProxy.addPushEventHandler(pushEventHandler)
    }
}
