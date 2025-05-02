@testable import CioInternalCommon
@testable import CioMessagingPush
@testable import CioMessagingPushFCM
import Foundation

class MessagingPushFCMMock: MessagingPushInstanceMock, MessagingPushFCMInstance {
    // MARK: - registerDeviceToken

    /// Number of times the function was called.
    @Atomic public private(set) var registerDeviceTokenFCMCallsCount = 0
    /// `true` if the function was ever called.
    public var registerDeviceTokenFCMCalled: Bool {
        registerDeviceTokenFCMCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    @Atomic public private(set) var registerDeviceTokenFCMReceivedArguments: String??
    /// Arguments from *all* of the times that the function was called.
    @Atomic public private(set) var registerDeviceTokenFCMReceivedInvocations: [String?] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var registerDeviceTokenFCMClosure: ((String?) -> Void)?

    /// Mocked function for `registerDeviceToken(fcmToken: String?)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func registerDeviceToken(fcmToken: String?) {
        mockCalled = true
        registerDeviceTokenFCMCallsCount += 1
        registerDeviceTokenFCMReceivedArguments = fcmToken
        registerDeviceTokenFCMReceivedInvocations.append(fcmToken)
        registerDeviceTokenFCMClosure?(fcmToken)
    }

    // MARK: - messaging

    /// Number of times the function was called.
    @Atomic public private(set) var didReceiveRegistrationTokenCallsCount = 0
    /// `true` if the function was ever called.
    public var didReceiveRegistrationTokenCalled: Bool {
        didReceiveRegistrationTokenCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    @Atomic public private(set) var didReceiveRegistrationTokenReceivedArguments: (messaging: Any, fcmToken: String?)?
    /// Arguments from *all* of the times that the function was called.
    @Atomic public private(set) var didReceiveRegistrationTokenReceivedInvocations: [(messaging: Any, fcmToken: String?)] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var didReceiveRegistrationTokenClosure: ((Any, String?) -> Void)?

    /// Mocked function for `messaging(_ messaging: Any, didReceiveRegistrationToken fcmToken: String?)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func messaging(_ messaging: Any, didReceiveRegistrationToken fcmToken: String?) {
        mockCalled = true
        didReceiveRegistrationTokenCallsCount += 1
        didReceiveRegistrationTokenReceivedArguments = (messaging: messaging, fcmToken: fcmToken)
        didReceiveRegistrationTokenReceivedInvocations.append((messaging: messaging, fcmToken: fcmToken))
        didReceiveRegistrationTokenClosure?(messaging, fcmToken)
    }

    // MARK: - application

    /// Number of times the function was called.
    @Atomic public private(set) var didRegisterForRemoteNotificationsCallsCount = 0
    /// `true` if the function was ever called.
    public var didRegisterForRemoteNotificationsCalled: Bool {
        didRegisterForRemoteNotificationsCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    @Atomic public private(set) var didRegisterForRemoteNotificationsReceivedArguments: (application: Any, deviceToken: Data)?
    /// Arguments from *all* of the times that the function was called.
    @Atomic public private(set) var didRegisterForRemoteNotificationsReceivedInvocations: [(application: Any, deviceToken: Data)] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var didRegisterForRemoteNotificationsClosure: ((Any, Data) -> Void)?

    /// Mocked function for `application(_ application: Any, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func application(_ application: Any, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        mockCalled = true
        didRegisterForRemoteNotificationsCallsCount += 1
        didRegisterForRemoteNotificationsReceivedArguments = (application: application, deviceToken: deviceToken)
        didRegisterForRemoteNotificationsReceivedInvocations.append((application: application, deviceToken: deviceToken))
        didRegisterForRemoteNotificationsClosure?(application, deviceToken)
    }

    // MARK: - application

    /// Number of times the function was called.
    @Atomic public private(set) var didFailToRegisterForRemoteNotificationsCallsCount = 0
    /// `true` if the function was ever called.
    public var didFailToRegisterForRemoteNotificationsCalled: Bool {
        didFailToRegisterForRemoteNotificationsCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    @Atomic public private(set) var didFailToRegisterForRemoteNotificationsReceivedArguments: (application: Any, error: Error)?
    /// Arguments from *all* of the times that the function was called.
    @Atomic public private(set) var didFailToRegisterForRemoteNotificationsReceivedInvocations: [(application: Any, error: Error)] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var didFailToRegisterForRemoteNotificationsClosure: ((Any, Error) -> Void)?

    /// Mocked function for `application(_ application: Any, didFailToRegisterForRemoteNotificationsWithError error: Error)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func application(_ application: Any, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        mockCalled = true
        didFailToRegisterForRemoteNotificationsCallsCount += 1
        didFailToRegisterForRemoteNotificationsReceivedArguments = (application: application, error: error)
        didFailToRegisterForRemoteNotificationsReceivedInvocations.append((application: application, error: error))
        didFailToRegisterForRemoteNotificationsClosure?(application, error)
    }
}
