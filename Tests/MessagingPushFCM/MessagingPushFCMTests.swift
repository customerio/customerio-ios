@testable import CioInternalCommon
@_spi(Internal) @testable import CioMessagingPush
@testable import CioMessagingPushFCM
import SharedTests
import XCTest

class MockMessagingPushInstanceImplementation {
    var initializeCalled = false
    var configReceived: MessagingPushConfigOptions?
    var returnValue: MessagingPushInstance!

    var implementation: MessagingPushInstanceImplementation {
        { config in
            self.initializeCalled = true
            self.configReceived = config
            return self.returnValue
        }
    }
}

class MessagingPushFCMTests: XCTestCase {
    // Mock classes
    var mockMessagingPush: MessagingPushInstanceMock!
    var mockAutoFetchDeviceToken: FCMAutoFetchDeviceTokenMock!
    var mockInitializeImplementation: MockMessagingPushInstanceImplementation!
    var mockInitializeImplementationForExtension: MockMessagingPushInstanceImplementation!

    // Save original dependencies
    var originalMessagingPushProvider: (() -> MessagingPushInstance)!
    var originalSetupAutoFetchDeviceToken: (() -> Void)!
    var originalInitializeImplementation: MessagingPushInstanceImplementation!
    var originalInitializeImplementationForExtension: MessagingPushInstanceImplementation!

    override func setUp() {
        super.setUp()

        UNUserNotificationCenter.swizzleNotificationCenter()

        // Create mocks
        mockMessagingPush = MessagingPushInstanceMock()
        mockAutoFetchDeviceToken = FCMAutoFetchDeviceTokenMock()
        mockInitializeImplementation = MockMessagingPushInstanceImplementation()
        mockInitializeImplementation.returnValue = mockMessagingPush
        mockInitializeImplementationForExtension = MockMessagingPushInstanceImplementation()
        mockInitializeImplementationForExtension.returnValue = mockMessagingPush

        // Save original dependencies
        originalMessagingPushProvider = MessagingPushFCMDependencies.messagingPushProvider
        originalSetupAutoFetchDeviceToken = MessagingPushFCMDependencies.setupAutoFetchDeviceToken
        originalInitializeImplementation = MessagingPushFCMDependencies.initializeImplementation

        // Replace with test mocks
        MessagingPushFCMDependencies.messagingPushProvider = { self.mockMessagingPush }
    }

    override func tearDown() {
        // Restore original dependencies
        MessagingPushFCMDependencies.messagingPushProvider = originalMessagingPushProvider
        MessagingPushFCMDependencies.setupAutoFetchDeviceToken = originalSetupAutoFetchDeviceToken
        MessagingPushFCMDependencies.initializeImplementation = originalInitializeImplementation

        mockMessagingPush = nil
        mockAutoFetchDeviceToken = nil
        mockInitializeImplementation = nil
        mockInitializeImplementationForExtension = nil

        UNUserNotificationCenter.unswizzleNotificationCenter()

        super.tearDown()
    }

    // MARK: - Initialize Method Tests

    func testInitialize_whenCalled_thenShouldCallImplementationAndSetupAutoFetch() {
        // Arrange
        var setupAutoFetchDeviceTokenCalled = false
        MessagingPushFCMDependencies.initializeImplementation = mockInitializeImplementation.implementation
        MessagingPushFCMDependencies.setupAutoFetchDeviceToken = {
            setupAutoFetchDeviceTokenCalled = true
        }

        let config = MessagingPushConfigOptions(
            logLevel: .info,
            cdpApiKey: "test-api-key",
            region: .US,
            autoFetchDeviceToken: true,
            autoTrackPushEvents: true,
            showPushAppInForeground: false
        )

        // Act
        let result = MessagingPushFCM.initialize(withConfig: config)

        // Assert
        XCTAssertTrue(mockInitializeImplementation.initializeCalled)
        XCTAssertEqual(mockInitializeImplementation.configReceived, config)
        XCTAssertTrue(setupAutoFetchDeviceTokenCalled)
        XCTAssertIdentical(result as AnyObject, mockMessagingPush)
    }

    // MARK: - Public API Tests

    func testRegisterDeviceToken_whenCalledWithValidToken_thenShouldCallMessagingPush() {
        // Arrange
        let fcmToken = "firebase-device-token"

        // Act
        MessagingPushFCM.shared.registerDeviceToken(fcmToken: fcmToken)

        // Assert
        XCTAssertTrue(mockMessagingPush.registerDeviceTokenCalled)
        XCTAssertEqual(mockMessagingPush.registerDeviceTokenReceivedArguments, fcmToken)
    }

    func testRegisterDeviceToken_whenCalledWithNilToken_thenShouldNotCallMessagingPush() {
        // Act
        MessagingPushFCM.shared.registerDeviceToken(fcmToken: nil)

        // Assert
        XCTAssertFalse(mockMessagingPush.registerDeviceTokenCalled)
    }

    func testMessagingDidReceiveRegistrationToken_whenCalledWithValidToken_thenShouldCallRegisterDeviceToken() {
        // Arrange
        let fcmToken = "firebase-device-token"

        // Act
        MessagingPushFCM.shared.messaging(NSObject(), didReceiveRegistrationToken: fcmToken)

        // Assert
        XCTAssertTrue(mockMessagingPush.registerDeviceTokenCalled)
        XCTAssertEqual(mockMessagingPush.registerDeviceTokenReceivedArguments, fcmToken)
    }

    func testMessagingDidReceiveRegistrationToken_whenCalledWithNilToken_thenShouldNotCallRegisterDeviceToken() {
        // Act
        MessagingPushFCM.shared.messaging(NSObject(), didReceiveRegistrationToken: nil)

        // Assert
        XCTAssertFalse(mockMessagingPush.registerDeviceTokenCalled)
    }

    func testApplicationDidFailToRegisterForRemoteNotifications_whenCalled_thenShouldCallDeleteDeviceToken() {
        // Arrange
        let error = NSError(domain: "test", code: 123, userInfo: nil)

        // Act
        MessagingPushFCM.shared.application(UIApplication.shared, didFailToRegisterForRemoteNotificationsWithError: error)

        // Assert
        XCTAssertTrue(mockMessagingPush.deleteDeviceTokenCalled)
    }

    func testDeleteDeviceToken_whenCalled_thenShouldCallMessagingPush() {
        // Act
        MessagingPushFCM.shared.deleteDeviceToken()

        // Assert
        XCTAssertTrue(mockMessagingPush.deleteDeviceTokenCalled)
    }

    func testTrackMetric_whenCalled_thenShouldCallMessagingPush() {
        // Arrange
        let deliveryID = "test-delivery-id"
        let event = Metric.delivered
        let deviceToken = "test-device-token"

        // Act
        MessagingPushFCM.shared.trackMetric(deliveryID: deliveryID, event: event, deviceToken: deviceToken)

        // Assert
        XCTAssertTrue(mockMessagingPush.trackMetricCalled)
        XCTAssertEqual(mockMessagingPush.trackMetricReceivedArguments?.deliveryID, deliveryID)
        XCTAssertEqual(mockMessagingPush.trackMetricReceivedArguments?.event, event)
        XCTAssertEqual(mockMessagingPush.trackMetricReceivedArguments?.deviceToken, deviceToken)
    }

    func testDidReceive_whenCalled_thenShouldCallMessagingPush() {
        // Arrange
        let content = UNMutableNotificationContent()
        content.title = "Test Title"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "test-identifier", content: content, trigger: trigger)

        var contentHandlerCalled = false
        let contentHandler: (UNNotificationContent) -> Void = { _ in
            contentHandlerCalled = true
        }

        mockMessagingPush.didReceiveNotificationRequestClosure = { _, _ in
            true
        }

        // Act
        let result = MessagingPushFCM.shared.didReceive(request, withContentHandler: contentHandler)

        // Assert
        XCTAssertTrue(mockMessagingPush.didReceiveNotificationRequestCalled)
        XCTAssertEqual(mockMessagingPush.didReceiveNotificationRequestReceivedArguments?.request.identifier, request.identifier)
        mockMessagingPush.didReceiveNotificationRequestReceivedArguments?.contentHandler(UNNotificationContent())
        XCTAssertTrue(contentHandlerCalled)
        XCTAssertTrue(result)
    }

    func testServiceExtensionTimeWillExpire_whenCalled_thenShouldCallMessagingPush() {
        // Act
        MessagingPushFCM.shared.serviceExtensionTimeWillExpire()

        // Assert
        XCTAssertTrue(mockMessagingPush.serviceExtensionTimeWillExpireCalled)
    }

    func testUserNotificationCenterDidReceive_whenCalled_thenShouldCallMessagingPush() {
        // Arrange
        let response = UNNotificationResponse.testInstance
        mockMessagingPush.userNotificationCenterClosure = { _, _ in
            nil
        }

        // Act
        let result = MessagingPushFCM.shared.userNotificationCenter(UNUserNotificationCenter.current(), didReceive: response)

        // Assert
        XCTAssertTrue(mockMessagingPush.userNotificationCenterCalled)
        XCTAssertEqual(mockMessagingPush.userNotificationCenterReceivedArguments?.response, response)
        XCTAssertEqual(result?.notification, nil)
    }

    func testUserNotificationCenterDidReceiveWithCompletionHandler_whenCalled_thenShouldCallMessagingPush() {
        // Arrange
        let response = UNNotificationResponse.testInstance
        var completionHandlerCalled = false
        let completionHandler = {
            completionHandlerCalled = true
        }
        mockMessagingPush.userNotificationCenter_withCompletionClosure = { _, _, _ in true }

        // Act
        let result = MessagingPushFCM.shared.userNotificationCenter(UNUserNotificationCenter.current(), didReceive: response, withCompletionHandler: completionHandler)

        // Assert
        XCTAssertTrue(mockMessagingPush.userNotificationCenter_withCompletionCalled)
        mockMessagingPush.userNotificationCenter_withCompletionReceivedArguments?.completionHandler()
        XCTAssertTrue(completionHandlerCalled)
        XCTAssertEqual(mockMessagingPush.userNotificationCenter_withCompletionReceivedArguments?.response, response)
        XCTAssertTrue(result)
    }
}
