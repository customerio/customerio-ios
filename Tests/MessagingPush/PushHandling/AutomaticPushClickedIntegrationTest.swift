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
    private var pushEventHandlerProxy: PushEventHandlerProxy {
        DIGraphShared.shared.pushEventHandlerProxy
    }

    override func setUp() {
        super.setUp()

        pushEventHandler = IOSPushEventListener(
            jsonAdapter: diGraphShared.jsonAdapter,
            pushEventHandlerProxy: pushEventHandlerProxy,
            moduleConfig: diGraphShared.messagingPushConfigOptions,
            pushClickHandler: pushClickHandler,
            pushHistory: diGraphShared.pushHistory,
            logger: diGraphShared.logger
        )
    }

    // MARK: push clicked

    func test_pushClicked_expectHandlePushClick() {
        let givenPush = PushNotificationStub.getPushSentFromCIO()

        // The order matters of push click handling
        pushClickHandler.assertWillHandleDeepLinkLast(for: givenPush)

        performPushAction(PushNotificationActionStub(push: givenPush, didClickOnPush: true))

        pushClickHandler.assertHandledPushClick(for: givenPush)
    }

    // MARK: push swiped away

    func test_pushSwipedAway_expectDoNotRunCodeWhenPushIsClicked() {
        let givenPush = PushNotificationStub.getPushSentFromCIO()

        performPushAction(PushNotificationActionStub(push: givenPush, didClickOnPush: false))

        pushClickHandler.assertDidNotHandlePushClick()
    }

    // MARK: When the CIO SDK is the only click handler in the app.

    func test_givenCioSdkOnlyPushHandler_givenClickedOnCioPush_expectEventHandled() {
        let givenPush = PushNotificationStub.getPushSentFromCIO()

        performPushAction(PushNotificationActionStub(push: givenPush, didClickOnPush: true))

        pushClickHandler.assertHandledPushClick(for: givenPush)
    }

    func test_givenCioSdkOnlyPushHandler_givenClickedOnPushNotSentFromCio_expectEventHandled() {
        let givenPush = PushNotificationStub.getPushNotSentFromCIO()

        performPushAction(PushNotificationActionStub(push: givenPush, didClickOnPush: true))

        pushClickHandler.assertDidNotHandlePushClick()
    }

    // MARK: When CIO SDK not only click handler in app.

    func test_givenOtherPushHandlers_givenClickedOnCioPush_expectPushClickHandledByCioSdk() {
        let expectOtherClickHandlerToGetCallback = expectation(description: "Receive a callback")

        let givenOtherPushHandler = getNewPushEventHandler()
        givenOtherPushHandler.onPushActionClosure = { _, onComplete in
            expectOtherClickHandlerToGetCallback.fulfill()
            onComplete()
        }
        addOtherPushEventHandler(givenOtherPushHandler)

        let givenPush = PushNotificationStub.getPushSentFromCIO()

        performPushAction(PushNotificationActionStub(push: givenPush, didClickOnPush: true))

        waitForExpectations()
        pushClickHandler.assertHandledPushClick(for: givenPush)
    }

    func test_givenOtherPushHandlers_givenClickedOnPushNotSentFromCio_expectPushClickHandledByOtherHandler() {
        let givenPush = PushNotificationStub.getPushNotSentFromCIO()
        let givenOtherPushHandler = getNewPushEventHandler()

        let expectOtherClickHandlerHandlesPush = expectation(description: "Other push handler should handle push.")
        givenOtherPushHandler.onPushActionClosure = { _, onComplete in
            expectOtherClickHandlerHandlesPush.fulfill()
            onComplete()
        }
        addOtherPushEventHandler(givenOtherPushHandler)

        performPushAction(PushNotificationActionStub(push: givenPush, didClickOnPush: true))

        waitForExpectations()

        pushClickHandler.assertDidNotHandlePushClick() // CIO SDK should not handle push.
    }

    // Important to test that 2+ 3rd party push handlers for some use cases.
    func test_givenMultiplePushHandlers_givenClickedOnCioPush_expectPushClickHandledByCioSdk() {
        let expectHandler1Called = expectation(description: "Receive a callback")
        let expectHandler2Called = expectation(description: "Receive a callback")

        let givenOtherPushHandler1 = getNewPushEventHandler()
        let givenOtherPushHandler2 = getNewPushEventHandler()
        givenOtherPushHandler1.onPushActionClosure = { _, onComplete in
            expectHandler1Called.fulfill()
            onComplete()
        }
        givenOtherPushHandler2.onPushActionClosure = { _, onComplete in
            expectHandler2Called.fulfill()
            onComplete()
        }
        addOtherPushEventHandler(givenOtherPushHandler1)
        addOtherPushEventHandler(givenOtherPushHandler2)

        let givenPush = PushNotificationStub.getPushSentFromCIO()

        performPushAction(PushNotificationActionStub(push: givenPush, didClickOnPush: true))

        waitForExpectations()
        pushClickHandler.assertHandledPushClick(for: givenPush)
    }

    // MARK: completion handler

    // All UserNotification framework functions for handling push events are async and have a callback closure.
    // These tests cover the expected behavior of the SDK and how callback closures are handled.

    func test_givenMultiplePushHandlers_givenClickedOnCioPush_givenOtherPushHandlerDoesNotCallCompletionHandler_expectCompletionHandlerDoesNotGetCalled() {
        let expectOtherClickHandlerToGetCallback = expectation(description: "Receive a callback")
        let givenPush = PushNotificationStub.getPushSentFromCIO()
        let givenOtherPushHandler = getNewPushEventHandler()

        givenOtherPushHandler.onPushActionClosure = { _, _ in
            // Do not call completion handler.
            expectOtherClickHandlerToGetCallback.fulfill()
        }
        addOtherPushEventHandler(givenOtherPushHandler)

        performPushAction(PushNotificationActionStub(push: givenPush, didClickOnPush: true), expectToCallCompletionHandler: false)

        waitForExpectations(for: [expectOtherClickHandlerToGetCallback])

        // If the completion handler does not get called, then the CIO SDK can only partially handle the push event.
        pushClickHandler.assertTrackedOpenPushMetric(for: givenPush)
        pushClickHandler.assertOpenedDeepLink(for: givenPush, false)
    }

    func test_givenMultiplePushHandlers_givenClickedOnCioPush_givenOtherPushHandlerCallsCompletionHandler_expectCioSdkHandlesPush() {
        let givenPush = PushNotificationStub.getPushSentFromCIO()
        let givenOtherPushHandler = getNewPushEventHandler()
        givenOtherPushHandler.onPushActionClosure = { _, onComplete in
            onComplete()
        }
        addOtherPushEventHandler(givenOtherPushHandler)

        performPushAction(PushNotificationActionStub(push: givenPush, didClickOnPush: true))

        // Assert that Cio SDK still handled push click, even though completion handler called by other push handler.
        pushClickHandler.assertHandledPushClick(for: givenPush)
    }

    // MARK: prevent infinite loops when forwarding push events to other push handlers

    /*
     Some 3rd party SDKs (such as FCM SDK) have an implementation of swizzling that can create an infinite loop with our SDK.

     Example scenario of infinite loop:
     - iOS delivers a push click event to our SDK via our `UNUserNotificationCenterDelegate` instance.
     - Our SDK forwards the push event to other the other `UNUserNotificationCenterDelegate` instances. For example, we forward it to the FCM SDK.
     - The FCM SDK's swizzling implementation involves making a call back to the host app's current UserNotificationCenter.delegate (which is our SDK). See code: https://github.com/firebase/firebase-ios-sdk/blob/5890db966963fd76cfd020d68c0067a7741bef06/FirebaseMessaging/Sources/FIRMessagingRemoteNotificationsProxy.m#L498-L504
     - When the FCM SDK does this, it means our SDK's `UNUserNotificationCenterDelegate` instance is called *again* to handle the same push event we're already handling. If our SDK handles this push event again by forwarding the event to the other `UNUserNotificationCenterDelegate` instances, an infinite loop would occur.
     */

    func test_onPushAction_givenMultiplePushClickHandlers_simulateFcmSdkSwizzlingBehavior_expectNoInfiniteLoop() {
        let givenPush = PushNotificationStub.getPushNotSentFromCIO()
        let givenOtherPushHandler = getNewPushEventHandler()
        let givenPushClickAction = PushNotificationActionStub(push: givenPush, didClickOnPush: true)

        let expectOtherClickHandlerHandlesPush = expectation(description: "Other push handler should handle push.")
        expectOtherClickHandlerHandlesPush.expectedFulfillmentCount = 1 // the other push click handler should only be called once, indicating an infinite loop is not created.
        givenOtherPushHandler.onPushActionClosure = { _, onComplete in
            expectOtherClickHandlerHandlesPush.fulfill()

            // Like the FCM SDK does, make a call back to the app's current `UNUserNotificationCenterDelegate` instance. We simulate this by performing a push click, again.
            self.performPushAction(givenPushClickAction, withCompletionHandler: onComplete)
        }
        addOtherPushEventHandler(givenOtherPushHandler)

        performPushAction(givenPushClickAction)

        waitForExpectations()

        pushClickHandler.assertDidNotHandlePushClick() // CIO SDK should not handle push.
    }

    func test_shouldDisplayPushAppInForeground_givenMultiplePushClickHandlers_simulateFcmSdkSwizzlingBehavior_expectNoInfiniteLoop() {
        let givenPush = PushNotificationStub.getPushNotSentFromCIO()
        let givenOtherPushHandler = getNewPushEventHandler()

        let expectOtherClickHandlerHandlesPush = expectation(description: "Other push handler should handle push.")
        expectOtherClickHandlerHandlesPush.expectedFulfillmentCount = 1 // the other push click handler should only be called once, indicating an infinite loop is not created.
        givenOtherPushHandler.shouldDisplayPushAppInForegroundClosure = { _, onComplete in
            expectOtherClickHandlerHandlesPush.fulfill()

            // Like the FCM SDK does, make a call back to the app's current `UNUserNotificationCenterDelegate` instance. We simulate this by sending the push event back to us.
            self.sendPushEventShouldShowPushAppInForeground(givenPush, withCompletionHandler: onComplete)
        }
        addOtherPushEventHandler(givenOtherPushHandler)

        sendPushEventShouldShowPushAppInForeground(givenPush)

        waitForExpectations()

        pushClickHandler.assertDidNotHandlePushClick() // CIO SDK should not handle push.
    }

    /*
        Some 3rd party SDKs (such as rnfirebase) when they handle a push event, they call the async completionHandler more then one time. The CIO SDK expects to only
     receive the completionHandler once, but it needs to handle the scenario where a 3rd party SDK calls it multiple times otherwise the SDK could crash.

     References:
     1. rnfirebase push event handler (RNFBMessagingUNUserNotificationCenter) can call the completionHandler twice:
     https://github.com/invertase/react-native-firebase/blob/d849667a1b3614c4a938c1f2bea892758831b368/packages/messaging/ios/RNFBMessaging/RNFBMessaging%2BUNUserNotificationCenter.m#L139
     https://github.com/invertase/react-native-firebase/blob/d849667a1b3614c4a938c1f2bea892758831b368/packages/messaging/ios/RNFBMessaging/RNFBMessaging%2BUNUserNotificationCenter.m#L143-L145 (when the CIO SDK gets called as original delegate)
     */

    func test_onPushAction_givenMultiplePushClickHandlers_thirdPartySdkCallsCompletionHandlerTwice_expectSdkDoesNotCrash() {
        let givenPush = PushNotificationStub.getPushNotSentFromCIO()
        let givenOtherPushHandler = getNewPushEventHandler()
        let givenPushClickAction = PushNotificationActionStub(push: givenPush, didClickOnPush: true)

        let expectOtherClickHandlerHandlesPush = expectation(description: "Other push handler should handle push.")
        expectOtherClickHandlerHandlesPush.expectedFulfillmentCount = 1 // the other push click handler should only be called once, indicating an infinite loop is not created.
        givenOtherPushHandler.onPushActionClosure = { _, onComplete in
            expectOtherClickHandlerHandlesPush.fulfill()

            onComplete() // First, call the completion handler.
            self.performPushAction(givenPushClickAction, withCompletionHandler: onComplete) // Second, the CIO SDK will call it when it is called.
        }
        addOtherPushEventHandler(givenOtherPushHandler)

        performPushAction(givenPushClickAction)

        waitForExpectations()

        // If the test succeeds without crashing and all expectations fulfilled, it's a successful test.
    }

    func test_shouldDisplayPushAppInForeground_givenMultiplePushClickHandlers_thirdPartySdkCallsCompletionHandlerTwice_expectSdkDoesNotCrash() {
        let givenPush = PushNotificationStub.getPushNotSentFromCIO()
        let givenOtherPushHandler = getNewPushEventHandler()

        let expectOtherClickHandlerHandlesPush = expectation(description: "Other push handler should handle push.")
        expectOtherClickHandlerHandlesPush.expectedFulfillmentCount = 1 // the other push click handler should only be called once, indicating an infinite loop is not created.
        givenOtherPushHandler.shouldDisplayPushAppInForegroundClosure = { _, onComplete in
            expectOtherClickHandlerHandlesPush.fulfill()

            onComplete(false) // First, call the completion handler.
            self.sendPushEventShouldShowPushAppInForeground(givenPush, withCompletionHandler: onComplete) // Second, the CIO SDK will call it when it is called.
        }
        addOtherPushEventHandler(givenOtherPushHandler)

        sendPushEventShouldShowPushAppInForeground(givenPush)

        waitForExpectations()

        // If the test succeeds without crashing and all expectations fulfilled, it's a successful test.
    }

    // MARK: local push notification support

    func test_givenClickOnLocalPush_expectEventHandled() {
        let givenLocalPush = PushNotificationStub.getLocalPush(pushId: .random)

        performPushAction(PushNotificationActionStub(push: givenLocalPush, didClickOnPush: true))

        pushClickHandler.assertDidNotHandlePushClick()
    }

    func test_givenClickOnLocalPush_expectOtherClickHandlerHandlesClickEvent() {
        let givenLocalPush = PushNotificationStub.getLocalPush(pushId: .random)

        let givenOtherPushHandler = getNewPushEventHandler()
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

        let givenOtherPushHandler = getNewPushEventHandler()
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
        pushEventHandler.onPushAction(pushAction, completionHandler: completionHandler)
    }

    func sendPushEventShouldShowPushAppInForeground(_ push: PushNotification, expectToCallCompletionHandler: Bool = true) {
        // Note: It's important that we test that the `withContentHandler` callback function gets called either by our SDK (when we handle it), or the 3rd party handler.
        //       We add an expectation to verify that 1 push click handler calls it.
        let expectCompletionHandlerCalled = expectation(description: "Expect completion handler called by a click handler")

        if expectToCallCompletionHandler {
            expectCompletionHandlerCalled.expectedFulfillmentCount = 1 // Test will fail if called 2+ times which could indicate a bug because only 1 push click handler should be calling it.
        } else {
            expectCompletionHandlerCalled.isInverted = true
        }

        sendPushEventShouldShowPushAppInForeground(push) { _ in
            expectCompletionHandlerCalled.fulfill()
        }

        waitForExpectations(for: [expectCompletionHandlerCalled])
    }

    func sendPushEventShouldShowPushAppInForeground(_ push: PushNotification, withCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        pushEventHandler.shouldDisplayPushAppInForeground(push, completionHandler: completionHandler)
    }

    func addOtherPushEventHandler(_ pushEventHandler: PushEventHandler) {
        pushEventHandlerProxy.addPushEventHandler(pushEventHandler)
    }
}
