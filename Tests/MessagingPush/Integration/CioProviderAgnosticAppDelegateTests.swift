@testable import CioInternalCommon
@_spi(Internal) @testable import CioMessagingPush
import SharedTests
import UIKit
import UserNotifications
import XCTest

class CioProviderAgnosticAppDelegateTests: XCTestCase {
    // Mock Classes
    var mockMessagingPush: MessagingPushInstanceMock!
    var mockAppDelegate: MockAppDelegate!
    var mockNotificationCenter: UserNotificationCenterIntegrationMock!
    var mockNotificationCenterDelegate: MockNotificationCenterDelegate!
    var mockLogger: LoggerMock!
    var appDelegate: CioProviderAgnosticAppDelegate!

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

        mockMessagingPush = MessagingPushInstanceMock()
        mockAppDelegate = MockAppDelegate()
        mockNotificationCenter = UserNotificationCenterIntegrationMock()
        mockNotificationCenterDelegate = MockNotificationCenterDelegate()
        mockLogger = LoggerMock()

        // Configure mock notification center with a delegate
        mockNotificationCenter.delegate = mockNotificationCenterDelegate

        // Create AppDelegate with mocks
        appDelegate = CioProviderAgnosticAppDelegate(
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
        appDelegate = nil

        UNUserNotificationCenter.unswizzleNotificationCenter()

        MessagingPush.appDelegateIntegratedExplicitely = false

        super.tearDown()
    }

    // MARK: - Tests for application(_:didFinishLaunchingWithOptions:)

    func testDidFinishLaunchingWithOptions_whenValidConfigIsUsed_thenTokenIsRequestedAndDelegateIsSet() {
        // Call the method
        let result = appDelegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Verify behavior
        XCTAssertTrue(MessagingPush.appDelegateIntegratedExplicitely)
        XCTAssertTrue(result)
        XCTAssertTrue(mockAppDelegate.didFinishLaunchingCalled)
        XCTAssertTrue(mockLogger.debugCallsCount == 1)
        XCTAssertTrue(mockLogger.debugReceivedInvocations.contains {
            $0.message.contains("CIO: Registering for remote notifications")
        })
        XCTAssertTrue(mockNotificationCenter.delegate === appDelegate)
    }

    func testDidFinishLaunchingWithOptions_whenValidConfigIsUsed_thenTokenIsNotRequested() {
        appDelegate = CioProviderAgnosticAppDelegate(
            messagingPush: mockMessagingPush,
            userNotificationCenter: { self.mockNotificationCenter },
            appDelegate: mockAppDelegate,
            config: { self.createMockConfig(autoFetchDeviceToken: false) },
            logger: mockLogger
        )

        // Call the method
        let result = appDelegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Verify behavior
        XCTAssertTrue(result)
        XCTAssertTrue(mockAppDelegate.didFinishLaunchingCalled)
        XCTAssertFalse(mockLogger.debugReceivedInvocations.contains {
            $0.message.contains("CIO: Registering for remote notifications")
        })
        XCTAssertTrue(mockNotificationCenter.delegate === appDelegate)
    }

    func testDidFinishLaunchingWithOptions_whenAutoTrackPushEventsIsDisabled_thenDelegateIsNotSet() {
        appDelegate = CioProviderAgnosticAppDelegate(
            messagingPush: mockMessagingPush,
            userNotificationCenter: { self.mockNotificationCenter },
            appDelegate: mockAppDelegate,
            config: { self.createMockConfig(autoTrackPushEvents: false) },
            logger: mockLogger
        )

        // This should not cause a conflict now since shouldIntegrateWithNotificationCenter is false
        let result = appDelegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Verify behavior
        XCTAssertTrue(result)
        XCTAssertTrue(mockAppDelegate.didFinishLaunchingCalled)
        XCTAssertTrue(mockLogger.debugReceivedInvocations.contains {
            $0.message.contains("CIO: Registering for remote notifications")
        })
        // Delegate should not be set on notification center
        XCTAssertNotEqual(mockNotificationCenter.delegate as? CioProviderAgnosticAppDelegate, appDelegate)
    }

    // MARK: - Tests for remote notification registration

    func testDidRegisterForRemoteNotifications_whenCalled_thenWrappedDelegateIsCalled() {
        // Setup
        let application = UIApplication.shared
        let deviceToken = "device_token".data(using: .utf8)!

        // Call the method
        appDelegate.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)

        // Verify behavior
        XCTAssertTrue(mockAppDelegate.didRegisterForRemoteNotificationsCalled)
        XCTAssertEqual(mockAppDelegate.deviceTokenReceived, deviceToken)
    }

    func testDidFailToRegisterForRemoteNotifications_whenCalled_thenWrappedDelegateAndMessagingPushAreCalled() {
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

    func testUserNotificationCenterDidReceive_whenNotificationCenterIntegrationIsEnabled_thenWrapperedDelegatesAreCalled() {
        // Configure mock return value
        mockMessagingPush.userNotificationCenterReturnValue = nil

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

    func testUserNotificationCenterDidReceive_whenWrappedNotificationCenterDelegateIsNil_thenNotificationCompletitionHandlerIsCalled() {
        // Create custom app delegate
        appDelegate = CioProviderAgnosticAppDelegate(
            messagingPush: mockMessagingPush,
            userNotificationCenter: { self.mockNotificationCenter },
            appDelegate: mockAppDelegate,
            config: { self.createMockConfig(autoTrackPushEvents: false) },
            logger: mockLogger
        )
        mockMessagingPush.userNotificationCenterReturnValue = nil
        var completionHandlerCalled = false
        let completionHandler = {
            completionHandlerCalled = true
        }
        _ = appDelegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Call the method
        appDelegate.userNotificationCenter(UNUserNotificationCenter.current(), didReceive: UNNotificationResponse.testInstance, withCompletionHandler: completionHandler)

        // Verify behavior
        XCTAssertTrue(completionHandlerCalled)
    }

    // MARK: - Tests for method forwarding

    func testResponds_whenSelectorIsProvided_thenItShouldCorrectlyDetectResponse() {
        // Test all implemented optional methods
        for selector in appDelegate.implementedOptionalMethods {
            XCTAssertTrue(appDelegate.responds(to: selector), "Should respond to \(selector)")
        }

        // Test implementation for methodimplemented by the wrapped app delegate
        let wrappedSelector = #selector(UIApplicationDelegate.applicationDidBecomeActive(_:))
        XCTAssertTrue(appDelegate.responds(to: wrappedSelector), "Should respond to wrapped delegate's selector \(wrappedSelector)")

        // Test a non-implemented method
        let nonImplementedSelector = #selector(UIApplicationDelegate.applicationDidEnterBackground(_:))
        XCTAssertFalse(appDelegate.responds(to: nonImplementedSelector), "Should not respond to \(nonImplementedSelector)")
    }

    func testForwardingTarget_whenSelectorIsProvided_thenItShouldCorrectlyDetectTarget() {
        // Test forwarding for an implemented method
        let implementedSelector = #selector(UIApplicationDelegate.application(_:didFinishLaunchingWithOptions:))
        XCTAssertEqual(appDelegate.forwardingTarget(for: implementedSelector) as? CioProviderAgnosticAppDelegate, appDelegate)

        // Test forwarding for a method implemented by the wrapped app delegate
        let wrappedSelector = #selector(UIApplicationDelegate.applicationDidBecomeActive(_:))
        XCTAssertEqual(appDelegate.forwardingTarget(for: wrappedSelector) as? MockAppDelegate, mockAppDelegate)

        // Test forwarding for a method not implemented by any delegate
        let nonImplementedSelector = #selector(UIApplicationDelegate.applicationDidEnterBackground(_:))
        XCTAssertNil(appDelegate.forwardingTarget(for: nonImplementedSelector))
    }

    // MARK: - Tests for extension methods

    func testUserNotificationCenterWillPresent_whenCalled_thenWrappedDelegateIsCalled() {
        // Setup
        var completonHandlerCalled = false
        let completionHandler: (UNNotificationPresentationOptions) -> Void = { _ in
            completonHandlerCalled = true
        }
        _ = appDelegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Call the method
        appDelegate.userNotificationCenter(UNUserNotificationCenter.current(), willPresent: UNNotification.testInstance, withCompletionHandler: completionHandler)

        // Verify behavior
        XCTAssertTrue(mockNotificationCenterDelegate.willPresentNotificationCalled)
        XCTAssertTrue(completonHandlerCalled)
    }

    func testUserNotificationCenterOpenSettingsFor_whenCalled_thenWrappedDelegateIsCalled() {
        // Setup
        _ = appDelegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Call the method
        appDelegate.userNotificationCenter(UNUserNotificationCenter.current(), openSettingsFor: UNNotification.testInstance)

        // Verify behavior
        XCTAssertTrue(mockNotificationCenterDelegate.openSettingsForNotificationCalled)
    }

    func testApplicationContinueUserActivity_whenCalled_thenWrappedDelegateIsCalled() {
        // Setup
        let userActivity = NSUserActivity(activityType: "test")
        let restorationHandler: ([UIUserActivityRestoring]?) -> Void = { _ in }

        // Call the method
        let result = appDelegate.application(UIApplication.shared, continue: userActivity, restorationHandler: restorationHandler)

        // Verify behavior
        XCTAssertTrue(mockAppDelegate.continueUserActivityCalled)
        XCTAssertTrue(result)
    }
}
