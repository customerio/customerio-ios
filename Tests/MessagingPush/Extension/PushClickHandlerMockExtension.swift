@testable import CioMessagingPush
import Foundation
import XCTest

/*
 Set of test utilities for testing when a push notification is clicked.

 It's recommended to use these functions in your test functions when you're using `PushClickHandlerMock`.
 */

// MARK: Assertions

extension PushClickHandlerMock {
    // It's important that when we process a push click, we open the deep link last. This is because when opening a deep link, the device browser could open and the app could be put into the background.
    // Before the app potentially goes into the background, perform all other push click handling.
    func assertWillHandleDeepLinkLast(for push: PushNotification) {
        // When deep link is handled, we expect all other click handling to have already been done.
        handleDeepLinkClosure = { _ in
            // We expect all other push click handling to have already happened.
            self.assertHandledPushClick(for: push)

            // XXX: This would be a good place to call: mock.verifyNoMoreInteractions(), like in Mockito, to be more confident that we are calling deep link last.
        }
    }

    // When a push click is handled in the SDK, we expect *all* of these steps are performed.
    func assertHandledPushClick(for push: PushNotification) {
        XCTAssertEqual(cleanupAfterPushInteractedWithCallsCount, 1)

        assertTrackedOpenPushMetric(for: push)
        assertOpenedDeepLink(for: push)
    }

    func assertTrackedOpenPushMetric(for push: PushNotification, _ didTrackMetric: Bool = true, expectedNumberOfCalls: Int = 1) {
        XCTAssertEqual(trackPushMetricsCalled, didTrackMetric)

        if didTrackMetric {
            XCTAssertEqual(trackPushMetricsCallsCount, expectedNumberOfCalls)
            XCTAssertEqual(trackPushMetricsReceivedArguments!.pushId, push.pushId)
        }
    }

    func assertOpenedDeepLink(for push: PushNotification, _ didOpenDeepLink: Bool = true, expectedNumberOfCalls: Int = 1) {
        XCTAssertEqual(handleDeepLinkCalled, didOpenDeepLink)

        if didOpenDeepLink {
            XCTAssertEqual(handleDeepLinkCallsCount, expectedNumberOfCalls)
            XCTAssertEqual(handleDeepLinkReceivedArguments?.cioDeepLink, push.cioDeepLink)
        }
    }

    func assertDidNotHandlePushClick() {
        XCTAssertFalse(trackPushMetricsCalled)
        XCTAssertFalse(handleDeepLinkCalled)
    }
}
