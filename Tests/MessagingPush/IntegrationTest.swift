@testable import CioInternalCommon
@testable import CioMessagingPush
import Foundation
import SharedTests
import UserNotifications

class IntegrationTest: SharedTests.IntegrationTest {
    private let notificationCenterMock = UserNotificationCenterMock()

    override func setUp() {
        setUp(shouldInitializeModule: false, modifySdkConfig: nil)
    }

    func setUp(shouldInitializeModule: Bool = true, modifySdkConfig: ((inout SdkConfig) -> Void)? = nil) {
        MessagingPush.resetSharedInstance()

        super.setUp(modifySdkConfig: modifySdkConfig)

        // CIO is already initialized from super class

        // Override dependencies
        // Mock UNUserNotificationCenter because using it crashes the test suite.
        diGraph.override(value: notificationCenterMock, forType: UserNotificationCenter.self)

        // Sets up features such as hooks for test to be more realistic to production
        if shouldInitializeModule {
            MessagingPush.initialize()
        }
    }
}
