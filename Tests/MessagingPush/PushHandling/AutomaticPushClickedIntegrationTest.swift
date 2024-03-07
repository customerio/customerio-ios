@testable import CioInternalCommon
@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

// Integration tests that simulate a push being clicked on a device and
// how our SDK handles that event.
class AutomaticPushClickedIntegrationTest: IntegrationTest {
    private var pushEventHandler: PushEventHandler!

    private let pushClickHandler = PushClickHandlerMock()
    private let pushEventHandlerProxy = PushEventHandlerProxyImpl()

    override func setUp() {
        super.setUp()

        pushEventHandler = IOSPushEventListener(
            jsonAdapter: diGraph.jsonAdapter,
            pushEventHandlerProxy: pushEventHandlerProxy,
            moduleConfig: MessagingPushConfigOptions(),
            pushClickHandler: pushClickHandler,
            pushHistory: diGraph.pushHistory,
            logger: diGraph.logger
        )
    }

    // MARK: push clicked

    func test_pushClicked_expectRunCodeWhenAPushIsClicked() {
        let givenPush = PushNotificationStub.getPushSentFromCIO()

        performPushAction(PushNotificationActionStub(push: givenPush, didClickOnPush: true))

        // We expect push click handler to be called when a push is clicked.
        XCTAssertTrue(pushClickHandler.pushClickedCalled)
    }

    // MARK: push swiped away

    func test_pushSwipedAway_expectDoNotRunCodeWhenPushIsClicked() {
        let givenPush = PushNotificationStub.getPushSentFromCIO()

        performPushAction(PushNotificationActionStub(push: givenPush, didClickOnPush: false))

        // We expect push click handler to be called when a push is clicked.
        XCTAssertFalse(pushClickHandler.mockCalled)
    }

    // MARK: When the CIO SDK is the only click handler in the app.

    func test_givenCioSdkOnlyPushHandler_givenClickedOnCioPush_expectEventHandled() {
        let givenPush = PushNotificationStub.getPushSentFromCIO()

        performPushAction(PushNotificationActionStub(push: givenPush, didClickOnPush: true))

        assertHandledClick(for: givenPush)
    }

    func test_givenCioSdkOnlyPushHandler_givenClickedOnPushNotSentFromCio_expectEventHandled() {
        let givenPush = PushNotificationStub.getPushNotSentFromCIO()

        performPushAction(PushNotificationActionStub(push: givenPush, didClickOnPush: true))

        assertNoPushHanding()
    }

    func test_givenCioSdkOnlyPushHandler_givenSwipedAwayPushPushSentFromCio_expectEventHandled() {
        let givenPush = PushNotificationStub.getPushSentFromCIO()

        performPushAction(PushNotificationActionStub(push: givenPush, didClickOnPush: false))

        assertHandledNoClick()
    }

    // MARK: When CIO SDK not only click handler in app.

    func test_givenOtherPushHandlers_givenClickedOnCioPush_expectPushClickHandledByCioSdk() {
        let expectOtherClickHandlerToGetCallback = expectation(description: "Receive a callback")

        let givenOtherPushHandler = PushEventHandlerMock()
        givenOtherPushHandler.onPushActionClosure = { _, onComplete in
            expectOtherClickHandlerToGetCallback.fulfill()
            onComplete()
        }
        addOtherPushEventHandler(givenOtherPushHandler)

        let givenPush = PushNotificationStub.getPushSentFromCIO()

        performPushAction(PushNotificationActionStub(push: givenPush, didClickOnPush: true))

        waitForExpectations()
        assertHandledClick(for: givenPush)
    }

    func test_givenOtherPushHandlers_givenClickedOnPushNotSentFromCio_expectPushClickHandledByOtherHandler() {
        let givenPush = PushNotificationStub.getPushNotSentFromCIO()
        let givenOtherPushHandler = PushEventHandlerMock()

        let expectOtherClickHandlerHandlesPush = expectation(description: "Other push handler should handle push.")
        givenOtherPushHandler.onPushActionClosure = { _, onComplete in
            expectOtherClickHandlerHandlesPush.fulfill()
            onComplete()
        }
        addOtherPushEventHandler(givenOtherPushHandler)

        performPushAction(PushNotificationActionStub(push: givenPush, didClickOnPush: true))

        waitForExpectations()

        assertNoPushHanding() // CIO SDK should not handle push.
    }

    // Important to test that 2+ 3rd party push handlers for some use cases.
    func test_givenMultiplePushHandlers_givenClickedOnCioPush_expectPushClickHandledByCioSdk() {
        let expectOtherPushHandlersCalled = expectation(description: "Receive a callback")
        expectOtherPushHandlersCalled.expectedFulfillmentCount = 2

        // In order to add 2+ push handlers to SDK, each class needs to have a unique name.
        // The SDK only accepts unique push event handlers. Creating this class makes each push handler unique.
        class PushEventHandlerMock2: PushEventHandlerMock {}

        let givenOtherPushHandler1 = PushEventHandlerMock()
        let givenOtherPushHandler2 = PushEventHandlerMock2()
        givenOtherPushHandler1.onPushActionClosure = { _, onComplete in
            expectOtherPushHandlersCalled.fulfill()
            onComplete()
        }
        givenOtherPushHandler2.onPushActionClosure = { _, onComplete in
            expectOtherPushHandlersCalled.fulfill()
            onComplete()
        }
        addOtherPushEventHandler(givenOtherPushHandler1)
        addOtherPushEventHandler(givenOtherPushHandler2)

        let givenPush = PushNotificationStub.getPushSentFromCIO()

        performPushAction(PushNotificationActionStub(push: givenPush, didClickOnPush: true))

        waitForExpectations()
        assertHandledClick(for: givenPush)
    }

    // MARK: completion handler

    // All UserNotification framework functions for handling push events are async and have a callback closure.
    // These tests cover the expected behavior of the SDK and how callback closures are handled.

    func test_givenMultiplePushHandlers_givenClickedOnCioPush_givenOtherPushHandlerDoesNotCallCompletionHandler_expectCompletionHandlerDoesNotGetCalled() {
        let expectOtherClickHandlerToGetCallback = expectation(description: "Receive a callback")
        let givenPush = PushNotificationStub.getPushSentFromCIO()
        let givenOtherPushHandler = PushEventHandlerMock()

        givenOtherPushHandler.onPushActionClosure = { _, _ in
            // Do not call completion handler.
            expectOtherClickHandlerToGetCallback.fulfill()
        }
        addOtherPushEventHandler(givenOtherPushHandler)

        performPushAction(PushNotificationActionStub(push: givenPush, didClickOnPush: true), expectToCallCompletionHandler: false)

        waitForExpectations(for: [expectOtherClickHandlerToGetCallback])

        // If the completion handler does not get called, then the CIO SDK never handles the click event.
        assertHandledNoClick()
    }

    func test_givenMultiplePushHandlers_givenClickedOnCioPush_givenOtherPushHandlerCallsCompletionHandler_expectCioSdkHandlesPush() {
        let givenPush = PushNotificationStub.getPushSentFromCIO()
        let givenOtherPushHandler = PushEventHandlerMock()
        givenOtherPushHandler.onPushActionClosure = { _, onComplete in
            onComplete()
        }
        addOtherPushEventHandler(givenOtherPushHandler)

        performPushAction(PushNotificationActionStub(push: givenPush, didClickOnPush: true))

        // Assert that Cio SDK still handled push click, even though completion handler called by other push handler.
        assertHandledClick(for: givenPush)
    }

    // MARK: prevent infinite loops with notification center proxy

    /*
     Some 3rd party SDKs (such as FCM SDK) have an implementation of swizzling that can create an infinite loop with our SDK. .

     Example scenario of infinite loop:
     - iOS delivers a push click event to our SDK via our `UNUserNotificationCenterDelegate` instance.
     - The push did not come from CIO, so the SDK forwards the event to other `UNUserNotificationCenterDelegate` instances, such as FCM SDK.
     - The FCM SDK's swizzling implementation involves making a call back to the host app's current UserNotificationCenter.delegate (which is our SDK). See code: https://github.com/firebase/firebase-ios-sdk/blob/5890db966963fd76cfd020d68c0067a7741bef06/FirebaseMessaging/Sources/FIRMessagingRemoteNotificationsProxy.m#L498-L504
     - This call means that our SDK's `UNUserNotificationCenterDelegate` instance is called *again* to handle this push event. Starting this series of steps over again, creating an infinite loop.
     */

    func test_givenMultiplePushClickHandlers_simulateFcmSdkSwizzlingBehavior_expectNoInfiniteLoop() {
        let givenPush = PushNotificationStub.getPushNotSentFromCIO()
        let givenOtherPushHandler = PushEventHandlerMock()
        let givenPushClickAction = PushNotificationActionStub(push: givenPush, didClickOnPush: true)

        let expectOtherClickHandlerHandlesPush = expectation(description: "Other push handler should handle push.")
        expectOtherClickHandlerHandlesPush.expectedFulfillmentCount = 1 // the other push click handler should only be called once, indicating an infinite loop is not created.
        givenOtherPushHandler.onPushActionClosure = { _, onComplete in
            // Like the FCM SDK does, make a call back to the app's current `UNUserNotificationCenterDelegate` instance. We simulate this by performing a push click, again.
            self.performPushAction(givenPushClickAction) {}

            expectOtherClickHandlerHandlesPush.fulfill()
            onComplete()
        }
        addOtherPushEventHandler(givenOtherPushHandler)

        performPushAction(givenPushClickAction)

        waitForExpectations()

        assertNoPushHanding() // CIO SDK should not handle push.
    }

    // MARK: local push notification support

    func test_givenClickOnLocalPush_expectEventHandled() {
        let givenLocalPush = PushNotificationStub.getLocalPush(pushId: .random)

        performPushAction(PushNotificationActionStub(push: givenLocalPush, didClickOnPush: true))

        assertNoPushHanding()
    }

    func test_givenClickOnLocalPush_expectOtherClickHandlerHandlesClickEvent() {
        let givenLocalPush = PushNotificationStub.getLocalPush(pushId: .random)

        let givenOtherPushHandler = PushEventHandlerMock()
        let expectOtherClickHandlerHandlesPush = expectation(description: "Other push handler should handle push.")
        expectOtherClickHandlerHandlesPush.expectedFulfillmentCount = 1
        givenOtherPushHandler.onPushActionClosure = { _, onComplete in
            expectOtherClickHandlerHandlesPush.fulfill()
            onComplete()
        }
        addOtherPushEventHandler(givenOtherPushHandler)

        performPushAction(PushNotificationActionStub(push: givenLocalPush, didClickOnPush: true))

        waitForExpectations()
    }

    func test_givenClickedOnMultipleLocalPushNotifications_expectEventHandleUniquePushNotifications() {
        // It's common for a local push to have a hard-coded, not unique push id. So, we are making 2 push notifications, both with the same ID to simulate this scenario.
        let givenHardCodedPushId = "hard-coded-id"
        let givenLocalPush = PushNotificationStub.getLocalPush(pushId: givenHardCodedPushId)
        let givenSecondLocalPush = PushNotificationStub.getLocalPush(pushId: givenHardCodedPushId)

        let givenOtherPushHandler = PushEventHandlerMock()
        let expectOtherClickHandlerHandlesPush = expectation(description: "Other push handler should handle push.")
        expectOtherClickHandlerHandlesPush.expectedFulfillmentCount = 2 // Expect click handler to be able to handle both pushes, because each push is unique.
        givenOtherPushHandler.onPushActionClosure = { _, onComplete in
            expectOtherClickHandlerHandlesPush.fulfill()
            onComplete()
        }
        addOtherPushEventHandler(givenOtherPushHandler)

        performPushAction(PushNotificationActionStub(push: givenLocalPush, didClickOnPush: true))
        performPushAction(PushNotificationActionStub(push: givenSecondLocalPush, didClickOnPush: true))

        waitForExpectations()
    }
}

extension AutomaticPushClickedIntegrationTest {
    func performPushAction(_ pushAction: PushNotificationAction, expectToCallCompletionHandler: Bool = true) {
        // Note: It's important that we test that the `withContentHandler` callback function gets called either by our SDK (when we handle it), or the 3rd party handler.
        //       We add an expectation to verify that 1 push click handler calls it.
        let expectCompletionHandlerCalled = expectation(description: "Expect completion handler called by a click handler")

        if expectToCallCompletionHandler {
            expectCompletionHandlerCalled.expectedFulfillmentCount = 1 // Test will fail if called 2+ times which could indicate a bug because only 1 push click handler should be calling it.
        } else {
            expectCompletionHandlerCalled.isInverted = true
        }

        performPushAction(pushAction) {
            expectCompletionHandlerCalled.fulfill()
        }

        waitForExpectations(for: [expectCompletionHandlerCalled])
    }

    func performPushAction(_ pushAction: PushNotificationAction, withCompletionHandler completionHandler: @escaping () -> Void) {
        pushEventHandler.onPushAction(pushAction, completionHandler: {
            completionHandler()
        })
    }

    func addOtherPushEventHandler(_ pushEventHandler: PushEventHandler) {
        pushEventHandlerProxy.addPushEventHandler(pushEventHandler)
    }

    func assertHandledClick(for push: PushNotification) {
        XCTAssertEqual(pushClickHandler.pushClickedCallsCount, 1)
        XCTAssertEqual(pushClickHandler.pushClickedReceivedArguments!.pushId, push.pushId)
    }

    func assertHandledNoClick() {
        XCTAssertFalse(pushClickHandler.pushClickedCalled)
    }

    func assertNoPushHanding() {
        XCTAssertFalse(pushClickHandler.mockCalled)
    }
}
