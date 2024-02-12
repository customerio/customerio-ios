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

    func test_givenMultiplePushHandlers_givenClickedOnCioPush_expectPushClickHandledByCioSdk() {
        let givenOtherPushHandler = PushEventHandlerMock()
        givenOtherPushHandler.onPushActionClosure = { _, _ in
            XCTFail("Should not have called other push handler.")
        }
        addOtherPushEventHandler(givenOtherPushHandler)

        let givenPush = PushNotificationStub.getPushSentFromCIO()

        performPushAction(PushNotificationActionStub(push: givenPush, didClickOnPush: true))

        assertHandledClick(for: givenPush)
    }

    func test_givenMultiplePushHandlers_givenClickedOnPushNotSentFromCio_expectPushClickHandledByOtherHandler() {
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
    func performPushAction(_ pushAction: PushNotificationAction) {
        // Note: It's important that we test that the `withContentHandler` callback function gets called either by our SDK (when we handle it), or the 3rd party handler.
        //       We add an expectation to verify that 1 push click handler calls it.
        let expectCompletionHandlerCalled = expectation(description: "Expect completion handler called by a click handler")
        expectCompletionHandlerCalled.expectedFulfillmentCount = 1 // Test will fail if called 2+ times which could indicate a bug because only 1 push click handler should be calling it.

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
