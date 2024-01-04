@testable import CioInternalCommon
@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

// TODO: Get all tests in this class compiling, and passing.
// These are failing tests. Demonstrating the use cases we are currently testing manually today.
// Note: Some of the syntax used in the tests below may need to change. At this point,
// what is most important is the use cases are all covered by tests.
class AutomaticPushClickHandlingIntegrationTest: IntegrationTest {
    // MARK: When the CIO SDK is the only click handler in the app.

    func test_givenCioSdkOnlyPushHandlerInApp_givenClickedOnCioPush_expectPushClickHandled() {
        setupAutomaticPushClickHandlingFeature()

        let givenPush = getPush(content: [
            "CIO": [
                "link": "TODO"
            ]
        ])

        clickOnPushNotification(givenPush)

        assert(push: givenPush, gotHandledByCioSdk: true)
    }

    func test_givenCioSdkOnlyPushHandlerInApp_givenClickedOnPushNotSentFromCIO_expectPushClickHandled() {
        setupAutomaticPushClickHandlingFeature()

        let givenPush = [
            "not-cio-push": [
                "link": "TODO"
            ]
        ]

        clickOnPushNotification(givenPush)

        assert(push: givenPush, gotHandledByCioSdk: false)
    }

    // MARK: Given multiple push click handlers in app. Other push click handler set before CIO SDK initialized

    func test_givenMultiplePushClickHandlers_givenOtherHandlerSetBeforeCioInitialized_givenClickedOnCioPush_expectPushClickHandled() {
        // Given a 3rd party push handler is already set on the app before CIO SDK is initialized.
        notificationCenterMock.currentDelegate = UNUserNotificationCenterDelegateMock()

        setupAutomaticPushClickHandlingFeature()

        let givenPush = getPush(content: [
            "CIO": [
                "link": "TODO"
            ]
        ])

        clickOnPushNotification(givenPush)

        assert(push: givenPush, gotHandledByCioSdk: true)
        assert(push: givenPush, gotHandledBy3rdParty: false)
    }

    func test_givenMultiplePushClickHandlers_givenOtherHandlerSetBeforeCioInitialized_givenClickedOnPushNotFromCio_expectPushClickHandled() {
        // Given a 3rd party push handler is already set on the app before CIO SDK is initialized.
        notificationCenterMock.currentDelegate = UNUserNotificationCenterDelegateMock()

        setupAutomaticPushClickHandlingFeature()

        let givenPush = [
            "not-cio-push": [
                "link": "TODO"
            ]
        ]

        clickOnPushNotification(givenPush)

        assert(push: givenPush, gotHandledByCioSdk: false)
        assert(push: givenPush, gotHandledBy3rdParty: true)
    }

    // MARK: Given multiple push click handlers in app. Other push click handler set after CIO SDK initialized

    func test_givenMultiplePushClickHandlers_givenOtherHandlerSetAfterCioInitialized_givenClickedOnCioPush_expectPushClickHandled() {
        setupAutomaticPushClickHandlingFeature()

        notificationCenterMock.currentDelegate = UNUserNotificationCenterDelegateMock()

        let givenPush = getPush(content: [
            "CIO": [
                "link": "TODO"
            ]
        ])

        clickOnPushNotification(givenPush)

        assert(push: givenPush, gotHandledByCioSdk: true)
        assert(push: givenPush, gotHandledBy3rdParty: false)
    }

    func test_givenMultiplePushClickHandlers_givenOtherHandlerSetAfterCioInitialized_givenClickedOnPushNotFromCio_expectPushClickHandled() {
        setupAutomaticPushClickHandlingFeature()

        notificationCenterMock.currentDelegate = UNUserNotificationCenterDelegateMock()

        let givenPush = [
            "not-cio-push": [
                "link": "TODO"
            ]
        ]

        clickOnPushNotification(givenPush)

        assert(push: givenPush, gotHandledByCioSdk: false)
        assert(push: givenPush, gotHandledBy3rdParty: true)
    }

    // MARK: prevent infinite loops with notification center proxy

    /*
     Some 3rd party SDKs (such as FCM SDK) have an implementation of swizzling that can create an infinite loop with our notification center proxy. We keep a history of push notifications that have been handled to prevent this infinite loop.

     Example scenario of infinite loop:
     - This `userNotificationCenter(didReceive:)` function gets called by OS when a push is clicked.
     - Our notification center proxy calls the FCM SDK’s `userNotificationCenter(didReceive:)` function. FCM's swizzling implementation involves making a call back to the host app's current UserNotificationCenter.delegate (which is our SDK). See code: https://github.com/firebase/firebase-ios-sdk/blob/5890db966963fd76cfd020d68c0067a7741bef06/FirebaseMessaging/Sources/FIRMessagingRemoteNotificationsProxy.m#L498-L504
     ... this call to the host app's current delegate means that this function is called again. Once this function is called again, we have gotten into an infinite loop.
     */

    func test_givenMultiplePushClickHandlers_expectOtherClickHandlerHandlesPush_expectInfiniteLoopPrevented() {
        setupAutomaticPushClickHandlingFeature()

        notificationCenterMock.currentDelegate = UNUserNotificationCenterDelegateMock()
        otherPushClickDelegate.userNotificationCenterDidReceiveCalled = { _ in
            // handle push click

            // What other SDKs (such as FCM SDK) may do in it's swizzling implementation.
            // Is to make a call to the host app's current UserNotificationCenter.delegate (which is our SDK).
            // This line of code is what could cause an infinite loop unless we prevent it.
            clickOnPushNotification(givenPush)
        }

        let givenPush = getPush(content: [
            "CIO": [
                "link": "TODO"
            ]
        ])

        clickOnPushNotification(givenPush)

        XCTAssertEqusl(pushClickHandlerMock.pushClickedCount, 1) // should only be handled 1 time
    }

    // MARK: local push notification support

    func test_givenMultiplePushClickHandlers_expectOtherClickHandlerHandlesPush_expectInfiniteLoopPrevented() {
        setupAutomaticPushClickHandlingFeature()

        notificationCenterMock.currentDelegate = UNUserNotificationCenterDelegateMock()
        otherPushClickDelegate.userNotificationCenterDidReceiveCalled = { _ in
            // handle push click
        }

        let givenLocalNotification = getLocalNotification(pushId: "hard-coded-non-unique-id")

        clickOnPushNotification(givenLocalNotification)

        XCTAssertEqusl(pushClickHandlerMock.pushClickedCount, 1) // should only be handled 1 time

        clickOnPushNotification(givenLocalNotification)

        XCTAssertEqusl(pushClickHandlerMock.pushClickedCount, 2) // should be handled again, even though we have already handled push with that push ID before.
    }
    
    // TODO: the test class here tests only when a push is clicked. Add test functions for when a push is received on the device and we need to determine if we should show the push while app in foreground or not. 
    // Another way to put it, we need to test our SDK's logic of: 
    // userNotificationCenter(willPresent:)
}

extension AutomaticPushClickHandlingInsetegrationTest {
    func setupAutomaticPushClickHandlingFeature() {
        // TODO: we might need to change this function body because we may not be able to run the swizzling code in the test function. Running this line below will setup the swizzling code.
        MessagingPush.initialize()
    }

    func clickOnPushNotification(_ pushContent: [AnyHashable: Any]) {
        // We are acting as if we are the iOS OS and a push notification got clicked on the device.

        // First, iOS will get the current UNUserNotificationCenterDelegate instance set on the host iOS app.
        let hostAppDelegate = notificationCenterMock.currentDelegate

        // Then, iOS will call this function on the delegate.
        // Note: It's important that we test that the `withContentHandler` callback function gets called either by our SDK (when we handle it), or the 3rd party handler.
        //       We add an expectation to verify that 1 push click handler calls it.
        let expectCompletionHandlerCalled = expectation(description: "Expect completion handler called by a click handler")
        expectCompletionHandlerCalled.expectedFulfillmentCount = 1 // Test will fail if called 2+ times which could indicate a bug because only 1 push click handler should be calling it.

        // TODO: We may need to change the syntax of this line below.
        // It's difficult to create an instance of UNNotificationRequest because it's initializer is internal.
        // Therefore, we may need to call a different function then the one below. However, we will make sure that we are still testing the logic of our SDK when this function is called in production.
        hostAppDelegate?.userNotificationCenter?(notificationCenterMock, didReceive: UNNotificationRequestMock(), withContentHandler: { _ in
            expectCompletionHandlerCalled.fulfill()
        })

        waitForExpectations(for: [expectCompletionHandlerCalled])
    }

    func asset(push expectedPush: [AnyHashable: Any], gotHandledByCioSdk: Bool) {
        // TODO: we will use a mocked push click handler to determine if the push was clicked or not in our integration tests. We can feel confident that if pushClickhandler.pushClicked() is called in our SDK, we handled it. What happens inside of pushClickHandler.pushClicked() is tested in unit tests, not here.
        if gotHandledByCioSdk {
            XCTAssertTrue(pushClickHandlerMock.pushClicked)
            XCTAssertEqual(pushClickHandlerMock.pushClickedArguemtns.push, expectedPush)
        } else {
            XCTAssertFalse(pushClickHandlerMock.pushClicked)
        }
    }
}
