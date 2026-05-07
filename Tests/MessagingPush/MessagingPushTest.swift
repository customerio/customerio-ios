import Foundation
import SharedTests
import UIKit
import UserNotifications
import XCTest

@testable import CioInternalCommon
@testable import CioMessagingPush

class MessagingPushTest: IntegrationTest {
    override func initializeSDKComponents() -> MessagingPushInstance? {
        // We want to manually initialize the module in test functions. So, override this function to disable automatic module initialization.
        nil
    }

    override func setUp() {
        super.setUp()
        UNUserNotificationCenter.swizzleNotificationCenter()
    }

    override func tearDown() {
        UNUserNotificationCenter.unswizzleNotificationCenter()
        MessagingPush.resetNotificationCenterDelegate()
        super.tearDown()
    }

    // MARK: initialize

    func test_initialize_whenAutoTrackPushEventsIsTrue_thenNotificationDelegateIsInstalled() {
        MessagingPush.initialize()

        XCTAssertTrue(UNUserNotificationCenter.current().delegate is CioNotificationCenterDelegate)
    }

    func test_initialize_whenAutoTrackPushEventsIsFalse_thenNotificationDelegateIsNotInstalled() {
        MessagingPush.initialize(
            withConfig: MessagingPushConfigBuilder()
                .autoTrackPushEvents(false)
                .build()
        )

        XCTAssertFalse(UNUserNotificationCenter.current().delegate is CioNotificationCenterDelegate)
    }

    func test_initialize_whenAutoTrackPushEventsIsTrue_thenExistingDelegateIsWrapped() {
        let existingDelegate = MockNotificationCenterDelegate()
        UNUserNotificationCenter.current().delegate = existingDelegate

        MessagingPush.initialize()

        // The proxy should be installed and the existing delegate captured inside it
        XCTAssertTrue(UNUserNotificationCenter.current().delegate is CioNotificationCenterDelegate)
        // Verify the wrapped delegate is called through the proxy
        var completionHandlerCalled = false
        UNUserNotificationCenter.current().delegate?.userNotificationCenter?(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { _ in completionHandlerCalled = true }
        )
        XCTAssertTrue(existingDelegate.willPresentNotificationCalled)
    }
}
