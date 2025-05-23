@testable import CioInternalCommon
@testable import CioMessagingPushFCM
import SharedTests
import UIKit
import XCTest

class MockMessagingIntegration: MessagingIntegration {
    var apnsToken: Data?
    var tokenCallCount = 0
    var tokenToReturn: String?
    var errorToReturn: Error?

    func token(completion: @escaping (String?, Error?) -> Void) {
        tokenCallCount += 1
        completion(tokenToReturn, errorToReturn)
    }
}

class FCMAutoFetchDeviceTokenTests: XCTestCase {
    var mockMessaging: MockMessagingIntegration!
    var mockMessagingPushFCM: MessagingPushFCMInstanceMock!
    var mockAppDelegate: MockAppDelegate!
    var autoFetchDeviceToken: FCMAutoFetchDeviceTokenImpl!
    var registerForRemoteNotificationCalled = false

    override func setUp() {
        super.setUp()

        mockMessaging = MockMessagingIntegration()
        mockMessagingPushFCM = MessagingPushFCMInstanceMock()
        mockAppDelegate = MockAppDelegate()
        registerForRemoteNotificationCalled = false

        autoFetchDeviceToken = FCMAutoFetchDeviceTokenImpl(
            messaging: { self.mockMessaging },
            messagingPushFCM: mockMessagingPushFCM,
            appDelegate: { self.mockAppDelegate },
            registerForRemoteNotification: { self.registerForRemoteNotificationCalled = true }
        )
    }

    override func tearDown() {
        mockMessaging = nil
        mockMessagingPushFCM = nil
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
        let instanceWithNilDelegate = FCMAutoFetchDeviceTokenImpl(
            messaging: { self.mockMessaging },
            messagingPushFCM: mockMessagingPushFCM,
            appDelegate: { nil },
            registerForRemoteNotification: { registerCalled = true }
        )

        // Act
        instanceWithNilDelegate.setup()

        // Assert - Register should not be called when app delegate is nil (early return)
        XCTAssertFalse(registerCalled)
    }

    // MARK: - Swizzled Method Tests

    func testApplicationDidRegisterForRemoteNotifications_whenCalled_thenAPNSTokenSetAndFCMTokenRequested() {
        // Arrange
        let deviceToken = "test_token".data(using: .utf8)!
        mockMessaging.tokenToReturn = "fcm_token_123"

        // Act
        autoFetchDeviceToken.application(UIApplication.shared, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)

        // Assert
        XCTAssertEqual(mockMessaging.apnsToken, deviceToken)
        XCTAssertEqual(mockMessaging.tokenCallCount, 1)
        XCTAssertTrue(mockMessagingPushFCM.registerDeviceTokenCalled)
        XCTAssertEqual(mockMessagingPushFCM.registerDeviceTokenReceivedArguments, "fcm_token_123")
    }

    func testApplicationDidRegisterForRemoteNotifications_whenCalledWithLargeToken_thenAPNSTokenSetAndFCMTokenRequested() {
        // Arrange
        let deviceToken = Data(repeating: 0xFF, count: 32)
        mockMessaging.tokenToReturn = "fcm_token_large"

        // Act
        autoFetchDeviceToken.application(UIApplication.shared, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)

        // Assert
        XCTAssertEqual(mockMessaging.apnsToken, deviceToken)
        XCTAssertEqual(mockMessaging.tokenCallCount, 1)
        XCTAssertTrue(mockMessagingPushFCM.registerDeviceTokenCalled)
        XCTAssertEqual(mockMessagingPushFCM.registerDeviceTokenReceivedArguments, "fcm_token_large")
    }

    func testApplicationDidRegisterForRemoteNotifications_whenFCMTokenIsNil_thenRegisterDeviceTokenNotCalled() {
        // Arrange
        let deviceToken = "test_token".data(using: .utf8)!
        mockMessaging.tokenToReturn = nil

        // Act
        autoFetchDeviceToken.application(UIApplication.shared, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)

        // Assert
        XCTAssertEqual(mockMessaging.apnsToken, deviceToken)
        XCTAssertEqual(mockMessaging.tokenCallCount, 1)
        XCTAssertFalse(mockMessagingPushFCM.registerDeviceTokenCalled)
    }

    func testApplicationDidRegisterForRemoteNotifications_whenFCMTokenRequestFails_thenRegisterDeviceTokenNotCalled() {
        // Arrange
        let deviceToken = "test_token".data(using: .utf8)!
        mockMessaging.errorToReturn = NSError(domain: "FCMError", code: 1, userInfo: nil)

        // Act
        autoFetchDeviceToken.application(UIApplication.shared, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)

        // Assert
        XCTAssertEqual(mockMessaging.apnsToken, deviceToken)
        XCTAssertEqual(mockMessaging.tokenCallCount, 1)
        XCTAssertFalse(mockMessagingPushFCM.registerDeviceTokenCalled)
    }

    func testApplicationDidFailToRegisterForRemoteNotifications_whenCalled_thenDeleteDeviceTokenCalled() {
        // Arrange
        let error = NSError(domain: "test", code: 1, userInfo: nil)

        // Act
        autoFetchDeviceToken.application(UIApplication.shared, didFailToRegisterForRemoteNotificationsWithError: error)

        // Assert
        XCTAssertTrue(mockMessagingPushFCM.deleteDeviceTokenCalled)
    }
}
