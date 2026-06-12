import Foundation
@testable import SharedTests
import UIKit
import UserNotifications
import XCTest

@testable import CioInternalCommon
@_spi(Internal) @testable import CioMessagingPush

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

        XCTAssertNotNil(MessagingPush.shared.installedNotificationCenterDelegate)
    }

    func test_initialize_whenAutoTrackPushEventsIsFalse_thenNotificationDelegateIsNotInstalled() {
        MessagingPush.initialize(
            withConfig: MessagingPushConfigBuilder()
                .autoTrackPushEvents(false)
                .build()
        )

        XCTAssertNil(MessagingPush.shared.installedNotificationCenterDelegate)
    }

    /// Verifies that the tracking path inside CioNotificationCenterDelegate — which casts messagingPush
    /// to the concrete MessagingPush type — does not swallow the completionHandler.
    /// initialize() is intentionally not called: the nil implementation returns early without
    /// accessing push properties (which would crash on unsafeBitCast test stubs), so the
    /// test confirms the cast succeeds and the graceful nil-implementation path still calls completionHandler.
    func test_didReceive_whenMessagingPushIsConcreteType_thenCompletionHandlerIsCalled() {
        let delegate = CioNotificationCenterDelegate(
            messagingPush: MessagingPush.shared,
            config: { MessagingPush.moduleConfig },
            wrappedDelegate: nil
        )

        var completionHandlerCalled = false
        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: UNNotificationResponse.testInstance,
            withCompletionHandler: { completionHandlerCalled = true }
        )

        XCTAssertTrue(completionHandlerCalled)
    }

    func test_initialize_whenAutoTrackPushEventsIsTrue_thenExistingDelegateIsWrapped() {
        let existingDelegate = MockNotificationCenterDelegate()
        UNUserNotificationCenter.current().delegate = existingDelegate

        MessagingPush.initialize()

        XCTAssertNotNil(MessagingPush.shared.installedNotificationCenterDelegate)
        MessagingPush.shared.installedNotificationCenterDelegate?.userNotificationCenter(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { _ in }
        )
        XCTAssertTrue(existingDelegate.willPresentNotificationCalled)
    }
}
