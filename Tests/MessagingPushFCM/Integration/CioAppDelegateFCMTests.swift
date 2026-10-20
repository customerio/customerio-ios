@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioMessagingPushMocks
@_spi(Internal) @testable import CioMessagingPush
@testable import CioMessagingPushFCM
import SharedTests
import UIKit
import UserNotifications
import XCTest

@objc(CioTestFCMAppLifecycleProvider)
private protocol TestFCMAppLifecycleProvider: NSObjectProtocol {
    func addApplicationLifeCycleDelegate(_ delegate: NSObject)
}

private final class FlutterLikeAppDelegate: NSObject, UIApplicationDelegate, TestFCMAppLifecycleProvider {
    weak static var latestInstance: FlutterLikeAppDelegate?

    var addedLifecycleDelegate: NSObject?

    override init() {
        super.init()
        Self.latestInstance = self
    }

    func addApplicationLifeCycleDelegate(_ delegate: NSObject) {
        addedLifecycleDelegate = delegate
    }
}

class CioAppDelegateFCMTests: XCTestCase {
    var appDelegateFCM: CioAppDelegate!

    // Mock Classes
    var mockMessagingPush: MessagingPushFCMMock!
    var mockAppDelegate: MockAppDelegate!
    var mockNotificationCenter: UserNotificationCenterIntegrationMock!
    var mockNotificationCenterDelegate: MockNotificationCenterDelegate!
    var mockFirebaseService: MockFirebaseService!
    var mockFirebaseServiceDelegate: MockFirebaseServiceDelegate!
    var mockLogger: LoggerMock!

    // Mock config for testing
    func createMockConfig(autoFetchDeviceToken: Bool = true, autoTrackPushEvents: Bool = true) -> MessagingPushConfigOptions {
        MessagingPushConfigOptions(
            logLevel: .info,
            cdpApiKey: "test-api-key",
            region: .US,
            autoFetchDeviceToken: autoFetchDeviceToken,
            autoTrackPushEvents: autoTrackPushEvents,
            showPushAppInForeground: false,
            appGroupId: nil
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

        mockLogger = LoggerMock()

        // Set up the FirebaseService on MessagingPushFCM.shared
        MessagingPushFCM.shared.firebaseService = mockFirebaseService

        appDelegateFCM = CioAppDelegate(
            messagingPush: mockMessagingPush,
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
        mockFirebaseService = nil
        mockFirebaseServiceDelegate = nil
        mockLogger = nil
        appDelegateFCM = nil

        // Clean up MessagingPushFCM.shared.firebaseService
        MessagingPushFCM.shared.firebaseService = nil

        UNUserNotificationCenter.unswizzleNotificationCenter()

        MessagingPush.appDelegateIntegratedExplicitly = false
        MessagingPush.resetNotificationCenterDelegate()

        super.tearDown()
    }

    func testDidFinishLaunching_whenCalled_thenSuperIsCalled() {
        // Call the method
        let result = appDelegateFCM.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        // Verify behavior
        XCTAssertTrue(result)
        XCTAssertTrue(mockAppDelegate.didFinishLaunchingCalled)
        // -- `registerForRemoteNotifications` is called
        XCTAssertTrue(mockLogger.debugReceivedInvocations.contains {
            $0.message.contains("CIO: Registering for remote notifications")
        })
    }

    func testWrapperConforms_whenWrappedDelegateConforms_thenObjectiveCInvocationIsForwarded() throws {
        let wrapper = CioAppDelegateWrapper<FlutterLikeAppDelegate>()
        let lifecycleDelegate = NSObject()
        let lifecycleProviderProtocol = try XCTUnwrap(NSProtocolFromString("CioTestFCMAppLifecycleProvider"))
        let addLifecycleDelegateSelector = #selector(TestFCMAppLifecycleProvider.addApplicationLifeCycleDelegate(_:))

        XCTAssertTrue(wrapper.conforms(to: lifecycleProviderProtocol))
        XCTAssertTrue(wrapper.responds(to: addLifecycleDelegateSelector))

        wrapper.perform(addLifecycleDelegateSelector, with: lifecycleDelegate)

        XCTAssertTrue(FlutterLikeAppDelegate.latestInstance?.addedLifecycleDelegate === lifecycleDelegate)
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
            appDelegate: mockAppDelegate,
            config: { self.createMockConfig(autoFetchDeviceToken: false) },
            logger: mockLogger
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

        // Verify behavior - forwarded as a Firebase token callback, so the SDK knows its type
        XCTAssertTrue(mockMessagingPush.didReceiveRegistrationTokenCalled)
        XCTAssertEqual(mockMessagingPush.didReceiveRegistrationTokenReceivedArguments?.fcmToken, fcmToken)
        XCTAssertFalse(mockMessagingPush.registerDeviceTokenFCMCalled)
    }

    func testDidReceiveRegistration_whenCalled_thenWrappedFirebaseServiceDelegateIsCalled() {
        _ = appDelegateFCM.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        mockFirebaseService.simulateRegistration("fid-value")

        XCTAssertEqual(mockFirebaseServiceDelegate.receivedRegistrations, ["fid-value"])
    }

    func testDidReceiveRegistration_whenCalled_thenInstallationIdIsForwardedToCIO() {
        _ = appDelegateFCM.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        mockFirebaseService.simulateRegistration("fid-value")

        XCTAssertEqual(mockMessagingPush.didReceiveRegistrationCallsCount, 1)
        XCTAssertEqual(mockMessagingPush.didReceiveRegistrationReceivedArguments?.installationId, "fid-value")
        XCTAssertFalse(mockFirebaseServiceDelegate.didReceiveRegistrationTokenCalled)
    }

    func testFirebaseServiceDelegate_whenDelegateHasNoFidSupport_thenFidRegistrationStillReachesCIO() {
        // A delegate written before FID support, e.g. a customer's own
        class TokenOnlyDelegate: FirebaseServiceDelegate {
            func didReceiveRegistrationToken(_ token: String?) {}
        }
        let tokenOnlyDelegate = TokenOnlyDelegate()
        mockFirebaseService.delegate = tokenOnlyDelegate
        _ = appDelegateFCM.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        mockFirebaseService.simulateRegistration("fid-value")

        XCTAssertEqual(mockMessagingPush.didReceiveRegistrationReceivedArguments?.installationId, "fid-value")
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
        XCTAssertFalse(mockMessagingPush.deleteDeviceTokenCalled)
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

    // MARK: - Fetching FCM registration on APN registration

    func testDidRegisterForRemoteNotifications_whenTokenMode_thenFetchedTokenIsRegistered() {
        let apnsToken = "apns_token".data(using: .utf8)!
        _ = appDelegateFCM.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        appDelegateFCM.application(UIApplication.shared, didRegisterForRemoteNotificationsWithDeviceToken: apnsToken)
        mockFirebaseService.simulateTokenSuccess("fcm-token")

        XCTAssertEqual(mockFirebaseService.apnsToken, apnsToken)
        XCTAssertEqual(mockFirebaseService.fetchTokenCallCount, 1)
        XCTAssertEqual(mockFirebaseService.fetchInstallationIdCallCount, 0)
        // Forwarded as a Firebase token callback, so the SDK knows its type
        XCTAssertEqual(mockMessagingPush.didReceiveRegistrationTokenReceivedInvocations.map(\.fcmToken), ["fcm-token"])
        XCTAssertFalse(mockMessagingPush.didReceiveRegistrationCalled)
        XCTAssertFalse(mockMessagingPush.registerDeviceTokenFCMCalled)
    }

    func testDidRegisterForRemoteNotifications_whenFidMode_thenFetchedFidIsRegistered() {
        let apnsToken = "apns_token".data(using: .utf8)!
        mockFirebaseService.mockIsInstallationIdEnabled = true
        _ = appDelegateFCM.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        appDelegateFCM.application(UIApplication.shared, didRegisterForRemoteNotificationsWithDeviceToken: apnsToken)
        mockFirebaseService.simulateInstallationIdSuccess("fid-value")

        XCTAssertEqual(mockFirebaseService.apnsToken, apnsToken)
        XCTAssertEqual(mockFirebaseService.fetchInstallationIdCallCount, 1)
        XCTAssertEqual(mockFirebaseService.fetchTokenCallCount, 0)
        // Forwarded as a Firebase FID callback, so the SDK knows its type
        XCTAssertEqual(mockMessagingPush.didReceiveRegistrationReceivedInvocations.map(\.installationId), ["fid-value"])
        XCTAssertFalse(mockMessagingPush.didReceiveRegistrationTokenCalled)
        XCTAssertFalse(mockMessagingPush.registerDeviceTokenFCMCalled)
    }

    func testDidRegisterForRemoteNotifications_whenFidFetchFails_thenNothingIsRegistered() {
        mockFirebaseService.mockIsInstallationIdEnabled = true
        _ = appDelegateFCM.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        appDelegateFCM.application(UIApplication.shared, didRegisterForRemoteNotificationsWithDeviceToken: Data())
        mockFirebaseService.simulateInstallationIdError(NSError(domain: "test", code: 1))

        XCTAssertFalse(mockMessagingPush.didReceiveRegistrationCalled)
        XCTAssertFalse(mockMessagingPush.registerDeviceTokenFCMCalled)
    }

    func testDidRegisterForRemoteNotifications_whenAutoFetchDeviceTokenIsDisabled_thenNothingIsFetched() {
        appDelegateFCM = CioAppDelegate(
            messagingPush: mockMessagingPush,
            appDelegate: mockAppDelegate,
            config: { self.createMockConfig(autoFetchDeviceToken: false) },
            logger: mockLogger
        )
        _ = appDelegateFCM.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        appDelegateFCM.application(UIApplication.shared, didRegisterForRemoteNotificationsWithDeviceToken: Data())

        XCTAssertTrue(mockAppDelegate.didRegisterForRemoteNotificationsCalled)
        XCTAssertNil(mockFirebaseService.apnsToken)
        XCTAssertEqual(mockFirebaseService.fetchTokenCallCount, 0)
        XCTAssertEqual(mockFirebaseService.fetchInstallationIdCallCount, 0)
    }

    func testFirebaseService_whenServiceHasNoFidSupport_thenDefaultsToTokenMode() {
        // A service written before FID support, e.g. an older CioFirebaseWrapper
        class TokenOnlyFirebaseService: FirebaseService {
            var apnsToken: Data?
            var delegate: FirebaseServiceDelegate?
            func fetchToken(completion: @escaping (String?, Error?) -> Void) {}
        }
        let service = TokenOnlyFirebaseService()
        var fetchedFid: String?
        var fetchCompleted = false

        service.fetchInstallationId { fid, _ in
            fetchedFid = fid
            fetchCompleted = true
        }

        XCTAssertFalse(service.isInstallationIdEnabled)
        XCTAssertTrue(fetchCompleted)
        XCTAssertNil(fetchedFid)
    }
}
