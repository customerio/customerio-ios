@testable import CioInternalCommon
@testable import CioMessagingPushAPN
import SharedTests
import UIKit
import XCTest

class APNAutoFetchDeviceTokenTests: XCTestCase {
    var mockMessagingPushAPN: MessagingPushAPNInstanceMock!
    var mockAppDelegate: MockAppDelegate!
    var autoFetchDeviceToken: APNAutoFetchDeviceTokenImpl!
    var registerForRemoteNotificationCalled = false

    override func setUp() {
        super.setUp()

        mockMessagingPushAPN = MessagingPushAPNInstanceMock()
        mockAppDelegate = MockAppDelegate()
        registerForRemoteNotificationCalled = false

        autoFetchDeviceToken = APNAutoFetchDeviceTokenImpl(
            messagingPushAPN: mockMessagingPushAPN,
            appDelegate: { self.mockAppDelegate },
            registerForRemoteNotification: { self.registerForRemoteNotificationCalled = true }
        )
    }

    override func tearDown() {
        mockMessagingPushAPN = nil
        mockAppDelegate = nil
        autoFetchDeviceToken = nil
        registerForRemoteNotificationCalled = false

        super.tearDown()
    }

    // MARK: - Setup Tests

    func testSetup_whenFirstCall_thenSetupCompletesAndRegisterCalled() {
        // Act
        autoFetchDeviceToken.setup()

        // Assert
        XCTAssertTrue(registerForRemoteNotificationCalled)
    }

    func testSetup_whenMultipleCalls_thenRegisterCalledOnlyOnce() {
        // Act
        autoFetchDeviceToken.setup()
        registerForRemoteNotificationCalled = false // Reset flag
        autoFetchDeviceToken.setup()
        autoFetchDeviceToken.setup()

        // Assert - Register should not be called again due to didSwizzle guard
        XCTAssertFalse(registerForRemoteNotificationCalled)
    }

    func testSetup_whenNilAppDelegate_thenSetupCompletesButRegisterNotCalled() {
        // Arrange
        var registerCalled = false
        let instanceWithNilDelegate = APNAutoFetchDeviceTokenImpl(
            messagingPushAPN: mockMessagingPushAPN,
            appDelegate: { nil },
            registerForRemoteNotification: { registerCalled = true }
        )

        // Act
        instanceWithNilDelegate.setup()

        // Assert - Register should not be called when app delegate is nil (early return)
        XCTAssertFalse(registerCalled)
    }

    // MARK: - Swizzled Method Tests

    func testApplicationDidRegisterForRemoteNotifications_whenCalled_thenRegisterDeviceTokenCalled() {
        // Arrange
        let deviceToken = "test_token".data(using: .utf8)!

        // Act
        autoFetchDeviceToken.application(UIApplication.shared, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)

        // Assert
        XCTAssertTrue(mockMessagingPushAPN.registerDeviceTokenCalled)
        XCTAssertEqual(mockMessagingPushAPN.registerDeviceTokenReceivedArguments, deviceToken)
    }

    func testApplicationDidRegisterForRemoteNotifications_whenCalledWithLargeToken_thenRegisterDeviceTokenCalledWithCorrectData() {
        // Arrange
        let deviceToken = Data(repeating: 0xFF, count: 32)

        // Act
        autoFetchDeviceToken.application(UIApplication.shared, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)

        // Assert
        XCTAssertTrue(mockMessagingPushAPN.registerDeviceTokenCalled)
        XCTAssertEqual(mockMessagingPushAPN.registerDeviceTokenReceivedArguments, deviceToken)
    }

    func testApplicationDidFailToRegisterForRemoteNotifications_whenCalled_thenDeleteDeviceTokenCalled() {
        // Arrange
        let error = NSError(domain: "test", code: 1, userInfo: nil)

        // Act
        autoFetchDeviceToken.application(UIApplication.shared, didFailToRegisterForRemoteNotificationsWithError: error)

        // Assert
        XCTAssertTrue(mockMessagingPushAPN.deleteDeviceTokenCalled)
    }
}
