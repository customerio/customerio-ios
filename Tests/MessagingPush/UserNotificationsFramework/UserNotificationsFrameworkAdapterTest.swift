@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

class UserNotificationsFrameworkAdapterTest: IntegrationTest {
    // MARK: UNUserNotificationCenterDelegate

    /**
     The SDK comes with a `UNUserNotificationCenterDelegate` instance that is provided to the OS. The OS keeps a reference to it and will call it to handle push notification events, such as when a push is clicked.

     It's very important that the object that the OS has in-memory, stays in-memory otherwise the SDK will not be called to handle push events.

     This test makes sure that the `UNUserNotificationCenterDelegate` instance stays in-memory, even after other SDK dependencies may be destroyed.
     */
    func test_expectSdkUNUserNotificationCenterDelegateInMemoryAfterSdkReinitialized() {
        // The SDK should already be initialized by test class.

        let sdkDelegate = diGraph.userNotificationsFrameworkAdapter.delegate

        // Test use case of re-initializing the SDK.
        //
        // The SDK gets re-initialized, especially in SDK wrapper SDKs. When the SDK does get re-initialized, many dependencies get destroyed from memory.
        uninitializeSDK()
        setUp()

        let sdkDelegateAfterReinitialize = diGraph.userNotificationsFrameworkAdapter.delegate

        // Checks that 2 instances are identical references in-memory.
        XCTAssertTrue(sdkDelegate === sdkDelegateAfterReinitialize)
    }
}
