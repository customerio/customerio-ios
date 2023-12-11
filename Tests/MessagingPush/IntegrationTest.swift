@testable import CioMessagingPush
import Foundation
import SharedTests

class IntegrationTest: SharedTests.IntegrationTest {
    private let notificationCenterMock = UserNotificationCenterMock()

    override func setUp() {
        setUp(shouldInitializeModule: true)
    }

    func setUp(shouldInitializeModule: Bool = true) {
        MessagingPush.resetSharedInstance()

        super.setUp()

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
