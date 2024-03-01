@testable import CioInternalCommon
@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

class AutomaticPushDeliveredAppInForegrondTest: IntegrationTest {
    private var pushEventHandler: PushEventHandler!

    private let pushClickHandler = PushClickHandlerMock()
    private let pushEventHandlerProxy = PushEventHandlerProxyImpl()

    // MARK: test handling when push delivered, app in foreground

    // When a push is delivered to an iOS device and the app is in the foreground, iOS gives the app the option to either display that push or to not display that push.

    func test_givenCioPushDelivered_givenSdkConfigDisplayPush_expectPushDisplayed() {
        configureSdk(shouldDisplayPushAppInForeground: true)

        let givenPush = PushNotificationStub.getPushSentFromCIO()

        let didPushGetDisplayed = deliverPush(givenPush)

        XCTAssertTrue(didPushGetDisplayed)
    }

    func test_givenCioPushDelivered_givenSdkConfigDoNotDisplayPush_expectPushNotDisplayed() {
        configureSdk(shouldDisplayPushAppInForeground: false)

        let givenPush = PushNotificationStub.getPushSentFromCIO()

        let didPushGetDisplayed = deliverPush(givenPush)

        XCTAssertFalse(didPushGetDisplayed)
    }

    func test_givenMultiplePushHandlers_givenNonCioPushDelivered_expectHandleEvent() {
        configureSdk(shouldDisplayPushAppInForeground: false)
        let givenPush = PushNotificationStub.getPushNotSentFromCIO()
        var otherPushHandlerCalled = false

        let givenOtherPushHandler = PushEventHandlerMock()
        givenOtherPushHandler.shouldDisplayPushAppInForegroundClosure = { _, onComplete in
            otherPushHandlerCalled = true

            onComplete(true)
        }
        addOtherPushEventHandler(givenOtherPushHandler)

        _ = deliverPush(givenPush)

        XCTAssertTrue(otherPushHandlerCalled)
    }

    func test_givenCioOnlyPushHandler_givenNonCioPushDelivered_expectHandleEvent() {
        configureSdk(shouldDisplayPushAppInForeground: true)

        let givenPush = PushNotificationStub.getPushNotSentFromCIO()

        let didPushGetDisplayed = deliverPush(givenPush)

        XCTAssertTrue(didPushGetDisplayed)
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

    func deliverPush(_ push: PushNotification) -> Bool {
        // Note: It's important that we test that the `withContentHandler` callback function gets called either by our SDK (when we handle it), or the 3rd party handler.
        let expectCompletionHandlerCalled = expectation(description: "Expect completion handler called by a handler")
        expectCompletionHandlerCalled.expectedFulfillmentCount = 1 // Test will fail if called 2+ times which could indicate a bug because only 1 push click handler should be calling it.

        var returnValueFromPushHandler = false

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
