@testable import CioInternalCommon
@_spi(Internal) @testable import CioMessagingPush
import SharedTests
import UIKit
import UserNotifications
import XCTest

class AppDelegateTests: XCTestCase {
    // Mock Classes
    var mockMessagingPush: MessagingPushInstanceMock!
    var mockAppDelegate: MockAppDelegate!
    var mockNotificationCenter: UserNotificationCenterIntegrationMock!
    var mockNotificationCenterDelegate: MockNotificationCenterDelegate!
    var mockLogger: LoggerMock!
    var appDelegate: AppDelegate!

    // Mock config for testing
    func createMockConfig(autoFetchDeviceToken: Bool = false, autoTrackPushEvents: Bool = false) -> MessagingPushConfigOptions {
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

        mockMessagingPush = MessagingPushInstanceMock()
        mockAppDelegate = MockAppDelegate()
        mockNotificationCenter = UserNotificationCenterIntegrationMock()
        mockNotificationCenterDelegate = MockNotificationCenterDelegate()
        mockLogger = LoggerMock()

        // Configure mock notification center with a delegate
        mockNotificationCenter.delegate = mockNotificationCenterDelegate

        // Setup the MessagingPushInstanceMock to return configs
        mockMessagingPush.getConfigurationReturnValue = createMockConfig()

        // Create AppDelegate with mocks
        appDelegate = AppDelegate(
            messagingPush: mockMessagingPush,
            userNotificationCenter: { self.mockNotificationCenter },
            appDelegate: mockAppDelegate,
            logger: mockLogger
        )
    }

    override func tearDown() {
        mockMessagingPush = nil
        mockAppDelegate = nil
        mockNotificationCenter = nil
        mockNotificationCenterDelegate = nil
        mockLogger = nil
        appDelegate = nil
        
        UNUserNotificationCenter.unswizzleNotificationCenter()
        
        super.tearDown()
    }

    // MARK: - Tests for initialization and configuration

    func testAppDelegateInit() {
        XCTAssertNotNil(appDelegate)
        XCTAssertTrue(appDelegate.shouldSetNotificationCenterDelegate)
    }

    // MARK: - Tests for application(_:didFinishLaunchingWithOptions:)

    func testDidFinishLaunchingWithValidConfig() {
        // Setup
        mockMessagingPush.getConfigurationReturnValue = createMockConfig()

        // Create mock application for testing
        let application = UIApplication.shared

        // Call the method
        let result = appDelegate.application(application, didFinishLaunchingWithOptions: nil)

        // Verify behavior
        XCTAssertTrue(result)
        XCTAssertTrue(mockAppDelegate.didFinishLaunchingCalled)
        XCTAssertTrue(mockLogger.debugCallsCount == 1)
        XCTAssertTrue(mockLogger.debugReceivedInvocations.contains{
            $0.contains("CIO: Registering for remote notifications")
        })
        XCTAssertTrue(mockNotificationCenter.delegate === appDelegate)
    }

    func testDidFinishLaunchingWithConflictingConfig_AutoFetchDeviceToken() {
        // Setup
        mockMessagingPush.getConfigurationReturnValue = createMockConfig(autoFetchDeviceToken: true)

        // Create application for testing
        let application = UIApplication.shared

        // Call the method
        let result = appDelegate.application(application, didFinishLaunchingWithOptions: nil)

        // Verify behavior
        XCTAssertTrue(result)
        XCTAssertTrue(mockAppDelegate.didFinishLaunchingCalled)
        XCTAssertTrue(mockLogger.errorCallsCount > 0)
        XCTAssertTrue(mockLogger.errorReceivedInvocations.contains {
            $0.contains("'autoFetchDeviceToken' flag can't be enabled if AppDelegate is used")
        })
    }

    func testDidFinishLaunchingWithConflictingConfig_AutoTrackPushEvents() {
        // Setup
        mockMessagingPush.getConfigurationReturnValue = createMockConfig(autoTrackPushEvents: true)

        // Create application for testing
        let application = UIApplication.shared

        // Call the method
        let result = appDelegate.application(application, didFinishLaunchingWithOptions: nil)

        // Verify behavior
        XCTAssertTrue(result)
        XCTAssertTrue(mockAppDelegate.didFinishLaunchingCalled)
        XCTAssertTrue(mockLogger.errorCallsCount > 0)
        XCTAssertTrue(mockLogger.errorReceivedInvocations.contains { $0.contains("'autoTrackPushEvents' flag can't be enabled if AppDelegate is used with 'shouldSetNotificationCenterDelegate' flag set to true.") })
    }

    // MARK: - Tests for remote notification registration

    func testDidRegisterForRemoteNotifications() {
        // Setup
        let application = UIApplication.shared
        let deviceToken = "device_token".data(using: .utf8)!

        // Call the method
        appDelegate.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)

        // Verify behavior
        XCTAssertTrue(mockAppDelegate.didRegisterForRemoteNotificationsCalled)
        XCTAssertEqual(mockAppDelegate.deviceTokenReceived, deviceToken)
    }

    func testDidFailToRegisterForRemoteNotifications() {
        // Setup
        let application = UIApplication.shared
        let error = NSError(domain: "test", code: 123, userInfo: nil)

        // Call the method
        appDelegate.application(application, didFailToRegisterForRemoteNotificationsWithError: error)

        // Verify behavior
        XCTAssertTrue(mockAppDelegate.didFailToRegisterForRemoteNotificationsCalled)
        XCTAssertEqual((mockAppDelegate.errorReceived as NSError?)?.domain, "test")
        XCTAssertTrue(mockMessagingPush.deleteDeviceTokenCalled)
    }

    // MARK: - Tests for UNUserNotificationCenterDelegate methods

    func testUserNotificationCenterDidReceive() {
        // Configure mock return value
        mockMessagingPush.userNotificationCenterReturnValue = nil // Assuming normal push notification without CustomerIO payload

        var completionHandlerCalled = false
        let completionHandler = {
            completionHandlerCalled = true
        }
        _ = appDelegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)
        
        // Call the method
        appDelegate.userNotificationCenter(UNUserNotificationCenter.current(), didReceive: UNNotificationResponse.testInstance, withCompletionHandler: completionHandler)

        // Verify behavior
        XCTAssertTrue(mockMessagingPush.userNotificationCenterCalled)
        XCTAssertTrue(mockNotificationCenterDelegate.didReceiveNotificationResponseCalled)
        XCTAssertTrue(completionHandlerCalled)
    }

    // MARK: - Tests for method forwarding

    func testRespondsToSelector() {
        // Test all implemented optional methods
        for selector in appDelegate.implementedOptionalMethods {
            XCTAssertTrue(appDelegate.responds(to: selector), "Should respond to \(selector)")
        }

        // Test a non-implemented method
        let nonImplementedSelector = #selector(UIApplicationDelegate.applicationDidEnterBackground(_:))
        XCTAssertFalse(appDelegate.responds(to: nonImplementedSelector), "Should not respond to \(nonImplementedSelector)")
    }

    func testForwardingTargetForSelector() {
        // Test forwarding for an implemented method
        let implementedSelector = #selector(UIApplicationDelegate.application(_:didFinishLaunchingWithOptions:))
        XCTAssertEqual(appDelegate.forwardingTarget(for: implementedSelector) as? AppDelegate, appDelegate)

        // Test forwarding for a method implemented by the wrapped app delegate
        let wrappedSelector = #selector(UIApplicationDelegate.applicationDidBecomeActive(_:))
        XCTAssertEqual(appDelegate.forwardingTarget(for: wrappedSelector) as? MockAppDelegate, mockAppDelegate)

        // Test forwarding for a method not implemented by any delegate
        let nonImplementedSelector = #selector(UIApplicationDelegate.applicationDidEnterBackground(_:))
        XCTAssertNil(appDelegate.forwardingTarget(for: nonImplementedSelector))
    }

    // MARK: - Tests for extension methods

    func testUserNotificationCenterWillPresent() {
        // Setup
        var presentationOptionsCalled = false
        let completionHandler: (UNNotificationPresentationOptions) -> Void = { _ in
            presentationOptionsCalled = true
        }
        _ = appDelegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Call the method
        appDelegate.userNotificationCenter(UNUserNotificationCenter.current(), willPresent: UNNotification.testInstance, withCompletionHandler: completionHandler)

        // Verify behavior
        XCTAssertTrue(mockNotificationCenterDelegate.willPresentNotificationCalled)
        XCTAssertTrue(presentationOptionsCalled)
    }

    func testUserNotificationCenterOpenSettingsFor() {
        // Setup
        _ = appDelegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)
        
        // Call the method
        appDelegate.userNotificationCenter(UNUserNotificationCenter.current(), openSettingsFor: UNNotification.testInstance)

        // Verify behavior
        XCTAssertTrue(mockNotificationCenterDelegate.openSettingsForNotificationCalled)
    }

    func testApplicationContinueUserActivity() {
        // Setup
        let userActivity = NSUserActivity(activityType: "test")
        let restorationHandler: ([UIUserActivityRestoring]?) -> Void = { _ in }

        // Call the method
        let result = appDelegate.application(UIApplication.shared, continue: userActivity, restorationHandler: restorationHandler)

        // Verify behavior
        XCTAssertTrue(mockAppDelegate.continueUserActivityCalled)
        XCTAssertTrue(result)
    }

    // MARK: - Tests for custom subclass behavior

    func testShouldSetNotificationCenterDelegateOverride() {
        // Create a custom subclass that overrides the property
        class CustomAppDelegate: AppDelegate {
            override var shouldSetNotificationCenterDelegate: Bool {
                false
            }
        }

        // Create custom app delegate
        let customAppDelegate = CustomAppDelegate(
            messagingPush: mockMessagingPush,
            userNotificationCenter: { self.mockNotificationCenter },
            appDelegate: mockAppDelegate,
            logger: mockLogger
        )

        // Verify override works
        XCTAssertFalse(customAppDelegate.shouldSetNotificationCenterDelegate)

        // Test that didFinishLaunching respects the override
        mockMessagingPush.getConfigurationReturnValue = createMockConfig(autoTrackPushEvents: true)
        let application = UIApplication.shared

        // This should not cause a conflict now since shouldSetNotificationCenterDelegate is false
        let result = customAppDelegate.application(application, didFinishLaunchingWithOptions: nil)

        // Verify behavior
        XCTAssertTrue(result)
        XCTAssertTrue(mockAppDelegate.didFinishLaunchingCalled)
        // Delegate should not be set on notification center
        XCTAssertNotEqual(mockNotificationCenter.delegate as? CustomAppDelegate, customAppDelegate)
    }
}
