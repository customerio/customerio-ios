@testable import CioInternalCommon
@testable import CioMessagingPush
@testable import CioMessagingPushAPN
@testable import CioMessagingPushMocks
import UIKit
import XCTest

class MessagingPushAPNTests: XCTestCase {
    override func tearDown() {
        MessagingPush.resetTestEnvironment()
        super.tearDown()
    }

    // Calls the swizzled UIApplication overload, not the public Any one
    func testSwizzledDidFailToRegisterForRemoteNotifications_whenCalled_thenTokenNotDeleted() {
        let implementationMock = MessagingPushInstanceMock()
        MessagingPush.setUpSharedInstanceForUnitTest(
            implementation: implementationMock,
            diGraphShared: DIGraphShared.shared,
            config: MessagingPushConfigBuilder().build()
        )

        MessagingPushAPN.shared.application(UIApplication.shared, didFailToRegisterForRemoteNotificationsWithError: NSError(domain: "test", code: 1))

        XCTAssertFalse(implementationMock.deleteDeviceTokenCalled)
    }
}
