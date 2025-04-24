import Foundation
@testable import CioMessagingPushAPN
@testable import CioMessagingPush
@testable import CioInternalCommon

class APNMessagingPushMock: MessagingPushInstanceMock, MessagingPushAPNInstance {
    
    // MARK: - registerDeviceToken
    
    /// Number of times the function was called.
    @Atomic public private(set) var registerDeviceTokenAPNCallsCount = 0
    /// `true` if the function was ever called.
    public var registerDeviceTokenAPNCalled: Bool {
        return registerDeviceTokenAPNCallsCount > 0
    }
    /// The arguments from the *last* time the function was called.
    @Atomic public private(set) var registerDeviceTokenAPNReceivedArguments: (Data)?
    /// Arguments from *all* of the times that the function was called.
    @Atomic public private(set) var registerDeviceTokenAPNReceivedInvocations: [(Data)] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var registerDeviceTokenAPNClosure: ((Data) -> Void)?
    
    /// Mocked function for `registerDeviceToken(apnDeviceToken: Data)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func registerDeviceToken(apnDeviceToken: Data) {
        self.mockCalled = true
        registerDeviceTokenAPNCallsCount += 1
        registerDeviceTokenAPNReceivedArguments = (apnDeviceToken)
        registerDeviceTokenAPNReceivedInvocations.append((apnDeviceToken))
        registerDeviceTokenAPNClosure?(apnDeviceToken)
    }
    
    // MARK: - application
    
    /// Number of times the function was called.
    @Atomic public private(set) var didRegisterForRemoteNotificationsCallsCount = 0
    /// `true` if the function was ever called.
    public var didRegisterForRemoteNotificationsCalled: Bool {
        return didRegisterForRemoteNotificationsCallsCount > 0
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
        self.mockCalled = true
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
        return didFailToRegisterForRemoteNotificationsCallsCount > 0
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
        self.mockCalled = true
        didFailToRegisterForRemoteNotificationsCallsCount += 1
        didFailToRegisterForRemoteNotificationsReceivedArguments = (application: application, error: error)
        didFailToRegisterForRemoteNotificationsReceivedInvocations.append((application: application, error: error))
        didFailToRegisterForRemoteNotificationsClosure?(application, error)
    }
}
