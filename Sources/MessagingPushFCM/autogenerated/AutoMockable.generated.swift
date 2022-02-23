// Generated using Sourcery 1.6.0 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT
// swiftlint:disable all

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif
import CioMessagingPush
import CioTracking

/**
######################################################
Documentation
######################################################

This automatically generated file you are viewing contains mock classes that you can use in your test suite. 

* How do you generate a new mock class? 

1. Mocks are generated from Swift protocols. So, you must make one. 

```
protocol FriendsRepository {
    func acceptFriendRequest<Attributes: Encodable>(attributes: Attributes, _ onComplete: @escaping () -> Void)
}

class AppFriendsRepository: FriendsRepository {
    ...
}
```

2. Have your new protocol extend `AutoMockable`:

```
protocol FriendsRepository: AutoMockable {
    func acceptFriendRequest<Attributes: Encodable>(
        // sourcery:Type=Encodable
        attributes: Attributes, 
        _ onComplete: @escaping () -> Void)
}
```

> Notice the use of `// sourcery:Type=Encodable` for the generic type parameter. Without this, the mock would 
fail to compile: `functionNameReceiveArguments = (Attributes)` because `Attributes` is unknown to this `var`. 
Instead, we give the parameter a different type to use for the mock. `Encodable` works in this case. 
It will require a cast in the test function code, however. 

3. Run the command `make generate` on your machine. The new mock should be added to this file. 

* How do you use the mocks in your test class? 

```
class ExampleViewModelTest: XCTestCase {
    var viewModel: ExampleViewModel!
    var exampleRepositoryMock: ExampleRepositoryMock!
    override func setUp() {
        exampleRepositoryMock = ExampleRepositoryMock()
        viewModel = AppExampleViewModel(exampleRepository: exampleRepositoryMock)
    }
}
```

Or, you may need to inject the mock in a different way using the DI.shared graph:

```
class ExampleTest: XCTestCase {
    var exampleViewModelMock: ExampleViewModelMock!
    var example: Example!
    override func setUp() {
        exampleViewModelMock = ExampleViewModelMock()
        DI.shared.override(.exampleViewModel, value: exampleViewModelMock, forType: ExampleViewModel.self)
        example = Example()
    }
}

```

*/

public class MessagingPushFCMMocks {
    public static var shared: MessagingPushFCMMocks = MessagingPushFCMMocks()

    public var mocks: [MessagingPushFCMMock] = []
    private init() {}

    func add(mock: MessagingPushFCMMock) {
        self.mocks.append(mock)
    }

    func resetAll() {
        self.mocks.forEach {
            $0.reset()
        }
    }
}

public protocol MessagingPushFCMMock {
    func reset()
}














/**
 Class to easily create a mocked version of the `MessagingPushFCMInstance` class. 
 This class is equipped with functions and properties ready for you to mock! 

 Note: This file is automatically generated. This means the mocks should always be up-to-date and has a consistent API.
 See the SDK documentation to learn the basics behind using the mock classes in the SDK. 
 */
public class MessagingPushFCMInstanceMock: MessagingPushFCMInstance, MessagingPushFCMMock {
    /// If *any* interactions done on mock. `true` if any method or property getter/setter called. 
    public var mockCalled: Bool = false // 

    public init() {
        MessagingPushFCMMocks.shared.add(mock: self)
    }


    public func reset() {
        self.mockCalled = false 

        registerDeviceTokenCallsCount = 0
        registerDeviceTokenReceivedArguments = nil 
        registerDeviceTokenReceivedInvocations = []
        didReceiveRegistrationTokenCallsCount = 0
        didReceiveRegistrationTokenReceivedArguments = nil 
        didReceiveRegistrationTokenReceivedInvocations = []
        didFailToRegisterForRemoteNotificationsCallsCount = 0
        didFailToRegisterForRemoteNotificationsReceivedArguments = nil 
        didFailToRegisterForRemoteNotificationsReceivedInvocations = []
        deleteDeviceTokenCallsCount = 0
        trackMetricCallsCount = 0
        trackMetricReceivedArguments = nil 
        trackMetricReceivedInvocations = []
    #if canImport(UserNotifications)
        didReceiveNotificationRequestCallsCount = 0
        didReceiveNotificationRequestReceivedArguments = nil 
        didReceiveNotificationRequestReceivedInvocations = []
    #endif 
    #if canImport(UserNotifications)
        serviceExtensionTimeWillExpireCallsCount = 0
    #endif 
    #if canImport(UserNotifications)
        userNotificationCenterReceivedResponseCallsCount = 0
        userNotificationCenterReceivedResponseReceivedArguments = nil 
        userNotificationCenterReceivedResponseReceivedInvocations = []
    #endif 
    }

    // MARK: - registerDeviceToken

    /// Number of times the function was called.  
    public private(set) var registerDeviceTokenCallsCount = 0
    /// `true` if the function was ever called. 
    public var registerDeviceTokenCalled: Bool {
        return registerDeviceTokenCallsCount > 0
    }    
    /// The arguments from the *last* time the function was called. 
    public private(set) var registerDeviceTokenReceivedArguments: (String?)?
    /// Arguments from *all* of the times that the function was called. 
    public private(set) var registerDeviceTokenReceivedInvocations: [(String?)] = []
    /** 
     Set closure to get called when function gets called. Great way to test logic or return a value for the function. 
     */
    public var registerDeviceTokenClosure: ((String?) -> Void)?

    /// Mocked function for `registerDeviceToken(fcmToken: String?)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func registerDeviceToken(fcmToken: String?) {
        self.mockCalled = true
        registerDeviceTokenCallsCount += 1
        registerDeviceTokenReceivedArguments = (fcmToken)
        registerDeviceTokenReceivedInvocations.append((fcmToken))
        registerDeviceTokenClosure?(fcmToken)
    }

    // MARK: - messaging

    /// Number of times the function was called.  
    public private(set) var didReceiveRegistrationTokenCallsCount = 0
    /// `true` if the function was ever called. 
    public var didReceiveRegistrationTokenCalled: Bool {
        return didReceiveRegistrationTokenCallsCount > 0
    }    
    /// The arguments from the *last* time the function was called. 
    public private(set) var didReceiveRegistrationTokenReceivedArguments: (messaging: Any, fcmToken: String?)?
    /// Arguments from *all* of the times that the function was called. 
    public private(set) var didReceiveRegistrationTokenReceivedInvocations: [(messaging: Any, fcmToken: String?)] = []
    /** 
     Set closure to get called when function gets called. Great way to test logic or return a value for the function. 
     */
    public var didReceiveRegistrationTokenClosure: ((Any, String?) -> Void)?

    /// Mocked function for `messaging(_ messaging: Any, didReceiveRegistrationToken fcmToken: String?)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func messaging(_ messaging: Any, didReceiveRegistrationToken fcmToken: String?) {
        self.mockCalled = true
        didReceiveRegistrationTokenCallsCount += 1
        didReceiveRegistrationTokenReceivedArguments = (messaging: messaging, fcmToken: fcmToken)
        didReceiveRegistrationTokenReceivedInvocations.append((messaging: messaging, fcmToken: fcmToken))
        didReceiveRegistrationTokenClosure?(messaging, fcmToken)
    }

    // MARK: - application

    /// Number of times the function was called.  
    public private(set) var didFailToRegisterForRemoteNotificationsCallsCount = 0
    /// `true` if the function was ever called. 
    public var didFailToRegisterForRemoteNotificationsCalled: Bool {
        return didFailToRegisterForRemoteNotificationsCallsCount > 0
    }    
    /// The arguments from the *last* time the function was called. 
    public private(set) var didFailToRegisterForRemoteNotificationsReceivedArguments: (application: Any, error: Error)?
    /// Arguments from *all* of the times that the function was called. 
    public private(set) var didFailToRegisterForRemoteNotificationsReceivedInvocations: [(application: Any, error: Error)] = []
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

    // MARK: - deleteDeviceToken

    /// Number of times the function was called.  
    public private(set) var deleteDeviceTokenCallsCount = 0
    /// `true` if the function was ever called. 
    public var deleteDeviceTokenCalled: Bool {
        return deleteDeviceTokenCallsCount > 0
    }    
    /** 
     Set closure to get called when function gets called. Great way to test logic or return a value for the function. 
     */
    public var deleteDeviceTokenClosure: (() -> Void)?

    /// Mocked function for `deleteDeviceToken()`. Your opportunity to return a mocked value and check result of mock in test code.
    public func deleteDeviceToken() {
        self.mockCalled = true
        deleteDeviceTokenCallsCount += 1
        deleteDeviceTokenClosure?()
    }

    // MARK: - trackMetric

    /// Number of times the function was called.  
    public private(set) var trackMetricCallsCount = 0
    /// `true` if the function was ever called. 
    public var trackMetricCalled: Bool {
        return trackMetricCallsCount > 0
    }    
    /// The arguments from the *last* time the function was called. 
    public private(set) var trackMetricReceivedArguments: (deliveryID: String, event: Metric, deviceToken: String)?
    /// Arguments from *all* of the times that the function was called. 
    public private(set) var trackMetricReceivedInvocations: [(deliveryID: String, event: Metric, deviceToken: String)] = []
    /** 
     Set closure to get called when function gets called. Great way to test logic or return a value for the function. 
     */
    public var trackMetricClosure: ((String, Metric, String) -> Void)?

    /// Mocked function for `trackMetric(deliveryID: String, event: Metric, deviceToken: String)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func trackMetric(deliveryID: String, event: Metric, deviceToken: String) {
        self.mockCalled = true
        trackMetricCallsCount += 1
        trackMetricReceivedArguments = (deliveryID: deliveryID, event: event, deviceToken: deviceToken)
        trackMetricReceivedInvocations.append((deliveryID: deliveryID, event: event, deviceToken: deviceToken))
        trackMetricClosure?(deliveryID, event, deviceToken)
    }

    // MARK: - didReceive

    #if canImport(UserNotifications)
    /// Number of times the function was called.  
    public private(set) var didReceiveNotificationRequestCallsCount = 0
    /// `true` if the function was ever called. 
    public var didReceiveNotificationRequestCalled: Bool {
        return didReceiveNotificationRequestCallsCount > 0
    }    
    /// The arguments from the *last* time the function was called. 
    public private(set) var didReceiveNotificationRequestReceivedArguments: (request: UNNotificationRequest, contentHandler: (UNNotificationContent) -> Void)?
    /// Arguments from *all* of the times that the function was called. 
    public private(set) var didReceiveNotificationRequestReceivedInvocations: [(request: UNNotificationRequest, contentHandler: (UNNotificationContent) -> Void)] = []
    /// Value to return from the mocked function. 
    public var didReceiveNotificationRequestReturnValue: Bool!
    /** 
     Set closure to get called when function gets called. Great way to test logic or return a value for the function. 
     The closure has first priority to return a value for the mocked function. If the closure returns `nil`, 
     then the mock will attempt to return the value for `didReceiveNotificationRequestReturnValue`
     */
    public var didReceiveNotificationRequestClosure: ((UNNotificationRequest, (UNNotificationContent) -> Void) -> Bool)?

    /// Mocked function for `didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void)`. Your opportunity to return a mocked value and check result of mock in test code.
    @discardableResult 
    public func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) -> Bool {
        self.mockCalled = true
        didReceiveNotificationRequestCallsCount += 1
        didReceiveNotificationRequestReceivedArguments = (request: request, contentHandler: contentHandler)
        didReceiveNotificationRequestReceivedInvocations.append((request: request, contentHandler: contentHandler))
        return didReceiveNotificationRequestClosure.map({ $0(request, contentHandler) }) ?? didReceiveNotificationRequestReturnValue
    }
    #endif 

    // MARK: - serviceExtensionTimeWillExpire

    #if canImport(UserNotifications)
    /// Number of times the function was called.  
    public private(set) var serviceExtensionTimeWillExpireCallsCount = 0
    /// `true` if the function was ever called. 
    public var serviceExtensionTimeWillExpireCalled: Bool {
        return serviceExtensionTimeWillExpireCallsCount > 0
    }    
    /** 
     Set closure to get called when function gets called. Great way to test logic or return a value for the function. 
     */
    public var serviceExtensionTimeWillExpireClosure: (() -> Void)?

    /// Mocked function for `serviceExtensionTimeWillExpire()`. Your opportunity to return a mocked value and check result of mock in test code.
    public func serviceExtensionTimeWillExpire() {
        self.mockCalled = true
        serviceExtensionTimeWillExpireCallsCount += 1
        serviceExtensionTimeWillExpireClosure?()
    }
    #endif 

    // MARK: - userNotificationCenter

    #if canImport(UserNotifications)
    /// Number of times the function was called.  
    public private(set) var userNotificationCenterReceivedResponseCallsCount = 0
    /// `true` if the function was ever called. 
    public var userNotificationCenterReceivedResponseCalled: Bool {
        return userNotificationCenterReceivedResponseCallsCount > 0
    }    
    /// The arguments from the *last* time the function was called. 
    public private(set) var userNotificationCenterReceivedResponseReceivedArguments: (center: UNUserNotificationCenter, response: UNNotificationResponse, completionHandler: () -> Void)?
    /// Arguments from *all* of the times that the function was called. 
    public private(set) var userNotificationCenterReceivedResponseReceivedInvocations: [(center: UNUserNotificationCenter, response: UNNotificationResponse, completionHandler: () -> Void)] = []
    /// Value to return from the mocked function. 
    public var userNotificationCenterReceivedResponseReturnValue: Bool!
    /** 
     Set closure to get called when function gets called. Great way to test logic or return a value for the function. 
     The closure has first priority to return a value for the mocked function. If the closure returns `nil`, 
     then the mock will attempt to return the value for `userNotificationCenterReceivedResponseReturnValue`
     */
    public var userNotificationCenterReceivedResponseClosure: ((UNUserNotificationCenter, UNNotificationResponse, () -> Void) -> Bool)?

    /// Mocked function for `userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) -> Bool {
        self.mockCalled = true
        userNotificationCenterReceivedResponseCallsCount += 1
        userNotificationCenterReceivedResponseReceivedArguments = (center: center, response: response, completionHandler: completionHandler)
        userNotificationCenterReceivedResponseReceivedInvocations.append((center: center, response: response, completionHandler: completionHandler))
        return userNotificationCenterReceivedResponseClosure.map({ $0(center, response, completionHandler) }) ?? userNotificationCenterReceivedResponseReturnValue
    }
    #endif 

}
