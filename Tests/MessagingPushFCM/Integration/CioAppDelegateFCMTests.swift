@testable import CioInternalCommon
@_spi(Internal) @testable import CioMessagingPush
@testable import CioMessagingPushFCM
import SharedTests
import UIKit
import UserNotifications
import XCTest

class CioAppDelegateFCMTests: XCTestCase {
    var appDelegateFCM: CioAppDelegate!

    // Mock Classes
    var mockMessagingPush: MessagingPushFCMMock!
    var mockAppDelegate: MockAppDelegate!
    var mockNotificationCenter: UserNotificationCenterIntegrationMock!
    var mockNotificationCenterDelegate: MockNotificationCenterDelegate!
    var mockFirebaseService: MockFirebaseService!
    var mockFirebaseServiceDelegate: MockFirebaseServiceDelegate!
    var outputter: AccumulatorLogOutputter!
    
    var logger: Logger!

    // Mock config for testing
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

        mockMessagingPush = MessagingPushFCMMock()

        mockAppDelegate = MockAppDelegate()

        mockNotificationCenter = UserNotificationCenterIntegrationMock()
        mockNotificationCenterDelegate = MockNotificationCenterDelegate()
        mockNotificationCenter.delegate = mockNotificationCenterDelegate

        mockFirebaseService = MockFirebaseService()
        mockFirebaseServiceDelegate = MockFirebaseServiceDelegate()
        mockFirebaseService.delegate = mockFirebaseServiceDelegate

        outputter = AccumulatorLogOutputter()
        logger = LoggerImpl(outputter: outputter)

        // Set up the FirebaseService on MessagingPushFCM.shared
        MessagingPushFCM.shared.firebaseService = mockFirebaseService

        appDelegateFCM = CioAppDelegate(
            messagingPush: mockMessagingPush,
            userNotificationCenter: { self.mockNotificationCenter },
            appDelegate: mockAppDelegate,
            config: { self.createMockConfig() },
            logger: logger
        )
    }

    override func tearDown() {
        mockMessagingPush = nil
        mockAppDelegate = nil
        mockNotificationCenter = nil
        mockNotificationCenterDelegate = nil
        mockFirebaseService = nil
        mockFirebaseServiceDelegate = nil
        logger = nil
        outputter = nil
        appDelegateFCM = nil

        // Clean up MessagingPushFCM.shared.firebaseService
        MessagingPushFCM.shared.firebaseService = nil

        UNUserNotificationCenter.unswizzleNotificationCenter()

        MessagingPush.appDelegateIntegratedExplicitly = false

        super.tearDown()
    }

    func testDidFinishLaunching_whenCalled_thenSuperIsCalled() {
        // Call the method
        let result = appDelegateFCM.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Verify behavior
        XCTAssertTrue(result)
        XCTAssertTrue(mockAppDelegate.didFinishLaunchingCalled)
        // -- `registerForRemoteNotifications` is called
        XCTAssertTrue(outputter.debugMessages.contains {
            $0.contains("CIO: Registering for remote notifications")
        })
    }

    func testDidFinishLaunching_whenCalled_thenFirebaseServiceDelegateIsSet() {
        // Call the method
        _ = appDelegateFCM.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Verify behavior - the CioAppDelegate should be set as the delegate on the FirebaseService
        XCTAssertTrue(mockFirebaseService.delegate === appDelegateFCM)
    }

    func testDidFinishLaunchings_whenAutoFetchDeviceTokenIsDisabled_thenFirebaseServiceDelegateIsNotSet() {
        appDelegateFCM = CioAppDelegate(
            messagingPush: mockMessagingPush,
            userNotificationCenter: { self.mockNotificationCenter },
            appDelegate: mockAppDelegate,
            config: { self.createMockConfig(autoFetchDeviceToken: false) },
            logger: logger
        )
        mockFirebaseService.delegate = nil

        // Call didFinishLaunching
        let result = appDelegateFCM.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Verify behavior
        XCTAssertTrue(result)
        XCTAssertTrue(mockAppDelegate.didFinishLaunchingCalled)
        XCTAssertNil(mockFirebaseService.delegate)
    }

    // MARK: - Test FirebaseServiceDelegate

    func testDidReceiveRegistrationToken_whenCalled_thenWrappedFirebaseServiceDelegateIsCalled() {
        // Setup
        let fcmToken = "test-fcm-token"
        _ = appDelegateFCM.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Call method directly
        appDelegateFCM.didReceiveRegistrationToken(fcmToken)

        // Verify behavior - the wrapped delegate should be called
        XCTAssertTrue(mockFirebaseServiceDelegate.didReceiveRegistrationTokenCalled)
        XCTAssertEqual(mockFirebaseServiceDelegate.receivedToken, fcmToken)
    }

    func testDidReceiveRegistrationToken_whenCalled_thenTokenIsForwardedToCIO() {
        // Setup
        let fcmToken = "test-fcm-token"
        _ = appDelegateFCM.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Call method directly
        appDelegateFCM.didReceiveRegistrationToken(fcmToken)

        // Verify behavior
        XCTAssertTrue(mockMessagingPush.registerDeviceTokenFCMCalled)
        XCTAssertEqual(mockMessagingPush.registerDeviceTokenFCMReceivedArguments, fcmToken)
    }

    // MARK: - Tests for inherited AppDelegate functionality

    func testDidFailToRegisterForRemoteNotifications_whenCalled_thenSuperIsCalled() {
        // Setup
        let application = UIApplication.shared
        let error = NSError(domain: "test", code: 123, userInfo: nil)

        // Call the method
        appDelegateFCM.application(application, didFailToRegisterForRemoteNotificationsWithError: error)

        // Verify behavior
        XCTAssertTrue(mockAppDelegate.didFailToRegisterForRemoteNotificationsCalled)
        XCTAssertEqual((mockAppDelegate.errorReceived as NSError?)?.domain, "test")
        XCTAssertTrue(mockMessagingPush.deleteDeviceTokenCalled == true)
    }

    // MARK: - Tests for UNUserNotificationCenterDelegate methods

    func testDidRegisterForRemoteNotifications_whenCalled_thenSuperIsCalled() {
        // Setup
        let deviceToken = "device_token".data(using: .utf8)!
        _ = appDelegateFCM.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Call the method
        appDelegateFCM.application(UIApplication.shared, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)

        // Verify behavior
        XCTAssertTrue(mockAppDelegate.didRegisterForRemoteNotificationsCalled)
        XCTAssertEqual(mockAppDelegate.deviceTokenReceived, deviceToken)
    }

    func testUserNotificationCenterDidReceive_whenCalled_thenSuperIsCalled() {
        // Setup
        _ = appDelegateFCM.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        var completionHandlerCalled = false
        let completionHandler = {
            completionHandlerCalled = true
        }

        // Call the method
        appDelegateFCM.userNotificationCenter(UNUserNotificationCenter.current(), didReceive: UNNotificationResponse.testInstance, withCompletionHandler: completionHandler)

        // Verify behavior
        XCTAssertTrue(mockNotificationCenterDelegate.didReceiveNotificationResponseCalled)
        XCTAssertTrue(completionHandlerCalled)
    }
}
