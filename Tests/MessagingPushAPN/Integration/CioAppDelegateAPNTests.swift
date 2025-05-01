@testable import CioInternalCommon
@testable import CioMessagingPush
@testable import CioMessagingPushAPN
import SharedTests
import UIKit
import UserNotifications
import XCTest

class CioAppDelegateAPNTests: XCTestCase {
    var appDelegateAPN: CioAppDelegate!

    // Mock Classes
    var mockMessagingPush: MessagingPushAPNMock!
    var mockAppDelegate: MockAppDelegate!
    var mockNotificationCenter: UserNotificationCenterIntegrationMock!
    var mockNotificationCenterDelegate: MockNotificationCenterDelegate!
    var mockLogger: LoggerMock!

    func createMockConfig(autoFetchDeviceToken: Bool = true, autoTrackPushEvents: Bool = true) -> MessagingPushConfigOptions {
        MessagingPushConfigOptions(
            logLevel: .info,
            cdpApiKey: "test-api-key",
            region: .US,
            autoFetchDeviceToken: autoFetchDeviceToken,
            autoTrackPushEvents: autoTrackPushEvents,
            showPushAppInForeground: false
        )
    }

    override func setUp() {
        super.setUp()

        UNUserNotificationCenter.swizzleNotificationCenter()

        mockMessagingPush = MessagingPushAPNMock()
        mockAppDelegate = MockAppDelegate()
        mockNotificationCenter = UserNotificationCenterIntegrationMock()
        mockNotificationCenterDelegate = MockNotificationCenterDelegate()
        mockLogger = LoggerMock()

        // Configure mock notification center with a delegate
        mockNotificationCenter.delegate = mockNotificationCenterDelegate

        // Create CioAppDelegate with mocks
        appDelegateAPN = CioAppDelegate(
            messagingPush: mockMessagingPush,
            userNotificationCenter: { self.mockNotificationCenter },
            appDelegate: mockAppDelegate,
            config: { self.createMockConfig() },
            logger: mockLogger
        )
    }

    override func tearDown() {
        mockMessagingPush = nil
        mockAppDelegate = nil
        mockNotificationCenter = nil
        mockNotificationCenterDelegate = nil
        mockLogger = nil
        appDelegateAPN = nil

        UNUserNotificationCenter.unswizzleNotificationCenter()

        MessagingPush.appDelegateIntegratedExplicitely = false

        super.tearDown()
    }

    // MARK: - Tests for APN-specific functionality

    func testDidRegisterForRemoteNotifications_whenCalled_thenSuperIsCalledANdDeviceTokenIsRegistered() {
        // Setup
        let deviceToken = "device_token".data(using: .utf8)!
        _ = appDelegateAPN.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Call the method
        appDelegateAPN.application(UIApplication.shared, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)

        // Verify behavior
        XCTAssertTrue(mockAppDelegate.didRegisterForRemoteNotificationsCalled)
        XCTAssertEqual(mockAppDelegate.deviceTokenReceived, deviceToken)

        // Verify APN-specific behavior: registerDeviceToken is called with the device token
        XCTAssertTrue(mockMessagingPush.registerDeviceTokenAPNCalled)
        XCTAssertEqual(mockMessagingPush.registerDeviceTokenAPNReceivedArguments, deviceToken)
    }

    // MARK: - Tests for inherited AppDelegate functionality

    func testDidFinishLaunchingWithOption_whenCalled_thenSuperIsCalled() {
        // Call the method
        let result = appDelegateAPN.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Verify behavior
        XCTAssertTrue(result)
        XCTAssertTrue(mockAppDelegate.didFinishLaunchingCalled)
        XCTAssertTrue(mockLogger.debugCallsCount == 1)
        XCTAssertTrue(mockLogger.debugReceivedInvocations.contains {
            $0.message.contains("CIO: Registering for remote notifications")
        })
        XCTAssertTrue(mockNotificationCenter.delegate === appDelegateAPN)
    }

    func testDidFailToRegisterForRemoteNotifications_whenCalled_thenSuperIsCalled() {
        // Setup
        let application = UIApplication.shared
        let error = NSError(domain: "test", code: 123, userInfo: nil)

        // Call the method
        appDelegateAPN.application(application, didFailToRegisterForRemoteNotificationsWithError: error)

        // Verify behavior
        XCTAssertTrue(mockAppDelegate.didFailToRegisterForRemoteNotificationsCalled)
        XCTAssertEqual((mockAppDelegate.errorReceived as NSError?)?.domain, "test")
        XCTAssertTrue(mockMessagingPush?.deleteDeviceTokenCalled == true)
    }

    // MARK: - Tests for UNUserNotificationCenterDelegate methods

    func testUserNotificationCenterDidReceive_whenCalled_thenSuperIsCalled() {
        // Setup
        _ = appDelegateAPN.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)
        mockMessagingPush.userNotificationCenterReturnValue = nil

        var completionHandlerCalled = false
        let completionHandler = {
            completionHandlerCalled = true
        }

        // Call the method
        appDelegateAPN.userNotificationCenter(UNUserNotificationCenter.current(), didReceive: UNNotificationResponse.testInstance, withCompletionHandler: completionHandler)

        // Verify behavior
        XCTAssertTrue(mockMessagingPush.userNotificationCenterCalled == true)
        XCTAssertTrue(mockNotificationCenterDelegate.didReceiveNotificationResponseCalled)
        XCTAssertTrue(completionHandlerCalled)
    }
}
