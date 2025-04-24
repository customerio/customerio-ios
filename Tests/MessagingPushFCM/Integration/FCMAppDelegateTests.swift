import XCTest
import UIKit
import UserNotifications
import FirebaseMessaging
import SharedTests
@testable import CioMessagingPushFCM
@testable import CioMessagingPush
@testable import CioInternalCommon

class FCMAppDelegateTests: XCTestCase {
    var fcmAppDelegate: FCMAppDelegate!
    
    // Mock Classes
    var mockMessagingPush: FCMMessagingPushMock!
    var mockAppDelegate: MockAppDelegate!
    var mockNotificationCenter: UserNotificationCenterIntegrationMock!
    var mockNotificationCenterDelegate: MockNotificationCenterDelegate!
    var mockMessaging: FirebaseMessagingIntegrationMock!
    var mockMessagingDelegate: MockMessagingDelegate!
    var mockLogger: LoggerMock!
    
    // Mock config for testing
    func createMockConfig(autoFetchDeviceToken: Bool = false, autoTrackPushEvents: Bool = false) -> MessagingPushConfigOptions {
        return MessagingPushConfigOptions(
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
        Messaging.swizzleMessaging()
        
        mockMessagingPush = FCMMessagingPushMock()
        mockMessagingPush.getConfigurationReturnValue = createMockConfig()
        
        mockAppDelegate = MockAppDelegate()
        
        mockNotificationCenter = UserNotificationCenterIntegrationMock()
        mockNotificationCenterDelegate = MockNotificationCenterDelegate()
        mockNotificationCenter.delegate = mockNotificationCenterDelegate
        
        mockMessaging = FirebaseMessagingIntegrationMock()
        mockMessagingDelegate = MockMessagingDelegate()
        mockMessaging.delegate = mockMessagingDelegate
        
        mockLogger = LoggerMock()
        
        fcmAppDelegate = FCMAppDelegate(
            messagingPush: mockMessagingPush,
            userNotificationCenter: { return self.mockNotificationCenter },
            firebaseMessaging: { self.mockMessaging },
            appDelegate: mockAppDelegate,
            logger: mockLogger
        )
    }
    
    override func tearDown() {
        mockMessagingPush = nil
        mockAppDelegate = nil
        mockNotificationCenter = nil
        mockNotificationCenterDelegate = nil
        mockMessaging = nil
        mockMessagingDelegate = nil
        mockLogger = nil
        fcmAppDelegate = nil
        
        Messaging.unswizzleMessaging()
        UNUserNotificationCenter.unswizzleNotificationCenter()
        
        super.tearDown()
    }
    
    // MARK: - Tests for initialization
    
    func testFCMAppDelegateInit() {
        XCTAssertNotNil(fcmAppDelegate)
        XCTAssertTrue(fcmAppDelegate.shouldSetNotificationCenterDelegate)
        XCTAssertTrue(fcmAppDelegate.shouldSetMessagingDelegate)
    }
    
    // MARK: - Tests for FCM-specific functionality
    
    func testDidFinishLaunching_shouldForwardCallToParentClass() {
        // Call the method
        let result = fcmAppDelegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)
        
        // Verify behavior
        XCTAssertTrue(result)
        XCTAssertTrue(mockAppDelegate.didFinishLaunchingCalled)
        // -- `registerForRemoteNotifications` is called
        XCTAssertTrue(mockLogger.debugReceivedInvocations.contains{
            $0.contains("CIO: Registering for remote notifications")
        })
    }
    
    func testDidFinishLaunching_shouldSetsMessagingDelegate() {
        // Call the method
        _ = fcmAppDelegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)
        
        // Verify behavior
        XCTAssertTrue(mockMessaging.delegate === fcmAppDelegate)
    }
    
    func testDidRegisterForRemoteNotifications_shouldForwardCallToParentClass() {
        // Setup
        let deviceToken = "device_token".data(using: .utf8)!
        _ = fcmAppDelegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)
        
        // Call the method
        fcmAppDelegate.application(UIApplication.shared, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
        
        // Verify behavior
        XCTAssertTrue(mockAppDelegate.didRegisterForRemoteNotificationsCalled)
        XCTAssertEqual(mockAppDelegate.deviceTokenReceived, deviceToken)
    }
    
    func testDidRegisterForRemoteNotifications_shouldForwardTokenToMessaging() {
        // Setup
        let deviceToken = "device_token".data(using: .utf8)!
        _ = fcmAppDelegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)
        
        // Call the method
        fcmAppDelegate.application(UIApplication.shared, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
        
        // Verify behavior
        XCTAssertTrue(mockMessaging.apnsTokenSetCalled)
        XCTAssertEqual(mockMessaging.underlyingApnsToken, deviceToken)
    }
    
    func testMessagingDidReceiveRegistrationToken_shouldForwardTokenToCIO() {
        // Setup
        let fcmToken = "test-fcm-token"
        _ = fcmAppDelegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)
        
        // Call method directly
        fcmAppDelegate.messaging(Messaging.messagingMock(), didReceiveRegistrationToken: fcmToken)
        
        // Verify behavior
        XCTAssertTrue(mockMessagingPush.registerDeviceTokenFCMCalled)
        XCTAssertEqual(mockMessagingPush.registerDeviceTokenFCMReceivedArguments, fcmToken)
    }
    
    func testMessagingDidReceiveRegistrationToken_shouldForwardTokenToWrappedObject() {
        // Setup
        let fcmToken = "test-fcm-token"
        _ = fcmAppDelegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)
        
        // Call method directly
        fcmAppDelegate.messaging(Messaging.messagingMock(), didReceiveRegistrationToken: fcmToken)
        
        // Verify behavior
        XCTAssertTrue(mockMessagingDelegate.didReceiveRegistrationTokenCalled)
        XCTAssertEqual(mockMessagingDelegate.fcmTokenReceived, fcmToken)
    }
    
    // MARK: - Tests for inherited AppDelegate functionality
    
    func testDidFailToRegisterForRemoteNotifications() {
        // Setup
        let application = UIApplication.shared
        let error = NSError(domain: "test", code: 123, userInfo: nil)
        
        // Call the method
        fcmAppDelegate.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
        
        // Verify behavior
        XCTAssertTrue(mockAppDelegate.didFailToRegisterForRemoteNotificationsCalled)
        XCTAssertEqual((mockAppDelegate.errorReceived as NSError?)?.domain, "test")
        XCTAssertTrue(mockMessagingPush.deleteDeviceTokenCalled == true)
    }
    
    // MARK: - Tests for UNUserNotificationCenterDelegate methods
    
    func testUserNotificationCenterDidReceive() {
        // Setup
        mockMessagingPush.userNotificationCenterReturnValue = nil
        _ = fcmAppDelegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        var completionHandlerCalled = false
        let completionHandler = {
            completionHandlerCalled = true
        }
        
        // Call the method
        fcmAppDelegate.userNotificationCenter(UNUserNotificationCenter.current(), didReceive: UNNotificationResponse.testInstance, withCompletionHandler: completionHandler)
        
        // Verify behavior
        XCTAssertTrue(mockMessagingPush.userNotificationCenterCalled == true)
        XCTAssertTrue(mockNotificationCenterDelegate.didReceiveNotificationResponseCalled)
        XCTAssertTrue(completionHandlerCalled)
    }
    
    // MARK: - Tests for shouldSetMessagingDelegate override
    
    func testShouldSetMessagingDelegateOverride() {
        // Create a custom subclass that overrides the property
        class CustomFCMAppDelegate: FCMAppDelegate {
            override var shouldSetMessagingDelegate: Bool {
                return false
            }
        }
        
        // Create custom app delegate
        let customFCMAppDelegate = CustomFCMAppDelegate(
            messagingPush: mockMessagingPush,
            userNotificationCenter: { self.mockNotificationCenter },
            firebaseMessaging: { self.mockMessaging },
            appDelegate: mockAppDelegate,
            logger: mockLogger
        )
        mockMessaging.delegate = nil
        
        // Verify override works
        XCTAssertFalse(customFCMAppDelegate.shouldSetMessagingDelegate)
        
        // Call didFinishLaunching
        let result = customFCMAppDelegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)
        
        // Verify behavior
        XCTAssertTrue(result)
        XCTAssertTrue(mockAppDelegate.didFinishLaunchingCalled)
        XCTAssertNil(mockMessaging.delegate)
    }
}
