// Generated using Sourcery 2.0.3 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT
// swiftlint:disable all

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif
import CioInternalCommon
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

/**
 Class to easily create a mocked version of the `AutomaticPushClickHandling` class.
 This class is equipped with functions and properties ready for you to mock!

 Note: This file is automatically generated. This means the mocks should always be up-to-date and has a consistent API.
 See the SDK documentation to learn the basics behind using the mock classes in the SDK.
 */
@available(iOSApplicationExtension, unavailable)
class AutomaticPushClickHandlingMock: AutomaticPushClickHandling, Mock {
    /// If *any* interactions done on mock. `true` if any method or property getter/setter called.
    var mockCalled: Bool = false //

    init() {
        Mocks.shared.add(mock: self)
    }

    public func resetMock() {
        startCallsCount = 0

        mockCalled = false // do last as resetting properties above can make this true
    }

    // MARK: - start

    /// Number of times the function was called.
    private(set) var startCallsCount = 0
    /// `true` if the function was ever called.
    var startCalled: Bool {
        startCallsCount > 0
    }

    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    var startClosure: (() -> Void)?

    /// Mocked function for `start()`. Your opportunity to return a mocked value and check result of mock in test code.
    func start() {
        mockCalled = true
        startCallsCount += 1
        startClosure?()
    }
}

/**
 Class to easily create a mocked version of the `DeepLinkUtil` class.
 This class is equipped with functions and properties ready for you to mock!

 Note: This file is automatically generated. This means the mocks should always be up-to-date and has a consistent API.
 See the SDK documentation to learn the basics behind using the mock classes in the SDK.
 */
class DeepLinkUtilMock: DeepLinkUtil, Mock {
    /// If *any* interactions done on mock. `true` if any method or property getter/setter called.
    var mockCalled: Bool = false //

    init() {
        Mocks.shared.add(mock: self)
    }

    public func resetMock() {
        handleDeepLinkCallsCount = 0
        handleDeepLinkReceivedArguments = nil
        handleDeepLinkReceivedInvocations = []

        mockCalled = false // do last as resetting properties above can make this true
    }

    // MARK: - handleDeepLink

    /// Number of times the function was called.
    private(set) var handleDeepLinkCallsCount = 0
    /// `true` if the function was ever called.
    var handleDeepLinkCalled: Bool {
        handleDeepLinkCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    private(set) var handleDeepLinkReceivedArguments: URL?
    /// Arguments from *all* of the times that the function was called.
    private(set) var handleDeepLinkReceivedInvocations: [URL] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    var handleDeepLinkClosure: ((URL) -> Void)?

    /// Mocked function for `handleDeepLink(_ deepLinkUrl: URL)`. Your opportunity to return a mocked value and check result of mock in test code.
    func handleDeepLink(_ deepLinkUrl: URL) {
        mockCalled = true
        handleDeepLinkCallsCount += 1
        handleDeepLinkReceivedArguments = deepLinkUrl
        handleDeepLinkReceivedInvocations.append(deepLinkUrl)
        handleDeepLinkClosure?(deepLinkUrl)
    }
}

/**
 Class to easily create a mocked version of the `MessagingPushInstance` class.
 This class is equipped with functions and properties ready for you to mock!

 Note: This file is automatically generated. This means the mocks should always be up-to-date and has a consistent API.
 See the SDK documentation to learn the basics behind using the mock classes in the SDK.
 */
public class MessagingPushInstanceMock: MessagingPushInstance, Mock {
    /// If *any* interactions done on mock. `true` if any method or property getter/setter called.
    public var mockCalled: Bool = false //

    public init() {
        Mocks.shared.add(mock: self)
    }

    public func resetMock() {
        registerDeviceTokenCallsCount = 0
        registerDeviceTokenReceivedArguments = nil
        registerDeviceTokenReceivedInvocations = []

        mockCalled = false // do last as resetting properties above can make this true
        deleteDeviceTokenCallsCount = 0

        mockCalled = false // do last as resetting properties above can make this true
        trackMetricCallsCount = 0
        trackMetricReceivedArguments = nil
        trackMetricReceivedInvocations = []

        mockCalled = false // do last as resetting properties above can make this true
        #if canImport(UserNotifications)
        didReceiveNotificationRequestCallsCount = 0
        didReceiveNotificationRequestReceivedArguments = nil
        didReceiveNotificationRequestReceivedInvocations = []
        #endif

        mockCalled = false // do last as resetting properties above can make this true
        #if canImport(UserNotifications)
        serviceExtensionTimeWillExpireCallsCount = 0
        #endif

        mockCalled = false // do last as resetting properties above can make this true
        #if canImport(UserNotifications)
        userNotificationCenter_withCompletionCallsCount = 0
        userNotificationCenter_withCompletionReceivedArguments = nil
        userNotificationCenter_withCompletionReceivedInvocations = []
        #endif

        mockCalled = false // do last as resetting properties above can make this true
        #if canImport(UserNotifications)
        userNotificationCenterCallsCount = 0
        userNotificationCenterReceivedArguments = nil
        userNotificationCenterReceivedInvocations = []
        #endif

        mockCalled = false // do last as resetting properties above can make this true
    }

    // MARK: - registerDeviceToken

    /// Number of times the function was called.
    public private(set) var registerDeviceTokenCallsCount = 0
    /// `true` if the function was ever called.
    public var registerDeviceTokenCalled: Bool {
        registerDeviceTokenCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var registerDeviceTokenReceivedArguments: String?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var registerDeviceTokenReceivedInvocations: [String] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var registerDeviceTokenClosure: ((String) -> Void)?

    /// Mocked function for `registerDeviceToken(_ deviceToken: String)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func registerDeviceToken(_ deviceToken: String) {
        mockCalled = true
        registerDeviceTokenCallsCount += 1
        registerDeviceTokenReceivedArguments = deviceToken
        registerDeviceTokenReceivedInvocations.append(deviceToken)
        registerDeviceTokenClosure?(deviceToken)
    }

    // MARK: - deleteDeviceToken

    /// Number of times the function was called.
    public private(set) var deleteDeviceTokenCallsCount = 0
    /// `true` if the function was ever called.
    public var deleteDeviceTokenCalled: Bool {
        deleteDeviceTokenCallsCount > 0
    }

    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var deleteDeviceTokenClosure: (() -> Void)?

    /// Mocked function for `deleteDeviceToken()`. Your opportunity to return a mocked value and check result of mock in test code.
    public func deleteDeviceToken() {
        mockCalled = true
        deleteDeviceTokenCallsCount += 1
        deleteDeviceTokenClosure?()
    }

    // MARK: - trackMetric

    /// Number of times the function was called.
    public private(set) var trackMetricCallsCount = 0
    /// `true` if the function was ever called.
    public var trackMetricCalled: Bool {
        trackMetricCallsCount > 0
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
        mockCalled = true
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
        didReceiveNotificationRequestCallsCount > 0
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
    public var didReceiveNotificationRequestClosure: ((UNNotificationRequest, @escaping (UNNotificationContent) -> Void) -> Bool)?

    /// Mocked function for `didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void)`. Your opportunity to return a mocked value and check result of mock in test code.
    @discardableResult
    public func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) -> Bool {
        mockCalled = true
        didReceiveNotificationRequestCallsCount += 1
        didReceiveNotificationRequestReceivedArguments = (request: request, contentHandler: contentHandler)
        didReceiveNotificationRequestReceivedInvocations.append((request: request, contentHandler: contentHandler))
        return didReceiveNotificationRequestClosure.map { $0(request, contentHandler) } ?? didReceiveNotificationRequestReturnValue
    }
    #endif

    // MARK: - serviceExtensionTimeWillExpire

    #if canImport(UserNotifications)
    /// Number of times the function was called.
    public private(set) var serviceExtensionTimeWillExpireCallsCount = 0
    /// `true` if the function was ever called.
    public var serviceExtensionTimeWillExpireCalled: Bool {
        serviceExtensionTimeWillExpireCallsCount > 0
    }

    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var serviceExtensionTimeWillExpireClosure: (() -> Void)?

    /// Mocked function for `serviceExtensionTimeWillExpire()`. Your opportunity to return a mocked value and check result of mock in test code.
    public func serviceExtensionTimeWillExpire() {
        mockCalled = true
        serviceExtensionTimeWillExpireCallsCount += 1
        serviceExtensionTimeWillExpireClosure?()
    }
    #endif

    // MARK: - userNotificationCenter

    #if canImport(UserNotifications)
    /// Number of times the function was called.
    public private(set) var userNotificationCenter_withCompletionCallsCount = 0
    /// `true` if the function was ever called.
    public var userNotificationCenter_withCompletionCalled: Bool {
        userNotificationCenter_withCompletionCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var userNotificationCenter_withCompletionReceivedArguments: (center: UNUserNotificationCenter, response: UNNotificationResponse, completionHandler: () -> Void)?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var userNotificationCenter_withCompletionReceivedInvocations: [(center: UNUserNotificationCenter, response: UNNotificationResponse, completionHandler: () -> Void)] = []
    /// Value to return from the mocked function.
    public var userNotificationCenter_withCompletionReturnValue: Bool!
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     The closure has first priority to return a value for the mocked function. If the closure returns `nil`,
     then the mock will attempt to return the value for `userNotificationCenter_withCompletionReturnValue`
     */
    public var userNotificationCenter_withCompletionClosure: ((UNUserNotificationCenter, UNNotificationResponse, @escaping () -> Void) -> Bool)?

    /// Mocked function for `userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) -> Bool {
        mockCalled = true
        userNotificationCenter_withCompletionCallsCount += 1
        userNotificationCenter_withCompletionReceivedArguments = (center: center, response: response, completionHandler: completionHandler)
        userNotificationCenter_withCompletionReceivedInvocations.append((center: center, response: response, completionHandler: completionHandler))
        return userNotificationCenter_withCompletionClosure.map { $0(center, response, completionHandler) } ?? userNotificationCenter_withCompletionReturnValue
    }
    #endif

    // MARK: - userNotificationCenter

    #if canImport(UserNotifications)
    /// Number of times the function was called.
    public private(set) var userNotificationCenterCallsCount = 0
    /// `true` if the function was ever called.
    public var userNotificationCenterCalled: Bool {
        userNotificationCenterCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var userNotificationCenterReceivedArguments: (center: UNUserNotificationCenter, response: UNNotificationResponse)?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var userNotificationCenterReceivedInvocations: [(center: UNUserNotificationCenter, response: UNNotificationResponse)] = []
    /// Value to return from the mocked function.
    public var userNotificationCenterReturnValue: CustomerIOParsedPushPayload?
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     The closure has first priority to return a value for the mocked function. If the closure returns `nil`,
     then the mock will attempt to return the value for `userNotificationCenterReturnValue`
     */
    public var userNotificationCenterClosure: ((UNUserNotificationCenter, UNNotificationResponse) -> CustomerIOParsedPushPayload?)?

    /// Mocked function for `userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) -> CustomerIOParsedPushPayload? {
        mockCalled = true
        userNotificationCenterCallsCount += 1
        userNotificationCenterReceivedArguments = (center: center, response: response)
        userNotificationCenterReceivedInvocations.append((center: center, response: response))
        return userNotificationCenterClosure.map { $0(center, response) } ?? userNotificationCenterReturnValue
    }
    #endif
}

/**
 Class to easily create a mocked version of the `PushClickHandler` class.
 This class is equipped with functions and properties ready for you to mock!

 Note: This file is automatically generated. This means the mocks should always be up-to-date and has a consistent API.
 See the SDK documentation to learn the basics behind using the mock classes in the SDK.
 */
@available(iOSApplicationExtension, unavailable)
class PushClickHandlerMock: PushClickHandler, Mock {
    /// If *any* interactions done on mock. `true` if any method or property getter/setter called.
    var mockCalled: Bool = false //

    init() {
        Mocks.shared.add(mock: self)
    }

    public func resetMock() {
        pushClickedCallsCount = 0
        pushClickedReceivedArguments = nil
        pushClickedReceivedInvocations = []

        mockCalled = false // do last as resetting properties above can make this true
    }

    // MARK: - pushClicked

    /// Number of times the function was called.
    private(set) var pushClickedCallsCount = 0
    /// `true` if the function was ever called.
    var pushClickedCalled: Bool {
        pushClickedCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    private(set) var pushClickedReceivedArguments: CustomerIOParsedPushPayload?
    /// Arguments from *all* of the times that the function was called.
    private(set) var pushClickedReceivedInvocations: [CustomerIOParsedPushPayload] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    var pushClickedClosure: ((CustomerIOParsedPushPayload) -> Void)?

    /// Mocked function for `pushClicked(_ push: CustomerIOParsedPushPayload)`. Your opportunity to return a mocked value and check result of mock in test code.
    func pushClicked(_ push: CustomerIOParsedPushPayload) {
        mockCalled = true
        pushClickedCallsCount += 1
        pushClickedReceivedArguments = push
        pushClickedReceivedInvocations.append(push)
        pushClickedClosure?(push)
    }
}

/**
 Class to easily create a mocked version of the `PushEventListener` class.
 This class is equipped with functions and properties ready for you to mock!

 Note: This file is automatically generated. This means the mocks should always be up-to-date and has a consistent API.
 See the SDK documentation to learn the basics behind using the mock classes in the SDK.
 */
class PushEventListenerMock: PushEventListener, Mock {
    /// If *any* interactions done on mock. `true` if any method or property getter/setter called.
    var mockCalled: Bool = false //

    init() {
        Mocks.shared.add(mock: self)
    }

    public func resetMock() {
        onPushActionCallsCount = 0
        onPushActionReceivedArguments = nil
        onPushActionReceivedInvocations = []

        mockCalled = false // do last as resetting properties above can make this true
        shouldDisplayPushAppInForegroundCallsCount = 0
        shouldDisplayPushAppInForegroundReceivedArguments = nil
        shouldDisplayPushAppInForegroundReceivedInvocations = []

        mockCalled = false // do last as resetting properties above can make this true
        newNotificationCenterDelegateSetCallsCount = 0
        newNotificationCenterDelegateSetReceivedArguments = nil
        newNotificationCenterDelegateSetReceivedInvocations = []

        mockCalled = false // do last as resetting properties above can make this true
        beginListeningCallsCount = 0

        mockCalled = false // do last as resetting properties above can make this true
    }

    // MARK: - onPushAction

    /// Number of times the function was called.
    private(set) var onPushActionCallsCount = 0
    /// `true` if the function was ever called.
    var onPushActionCalled: Bool {
        onPushActionCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    private(set) var onPushActionReceivedArguments: PushNotificationAction?
    /// Arguments from *all* of the times that the function was called.
    private(set) var onPushActionReceivedInvocations: [PushNotificationAction] = []
    /// Value to return from the mocked function.
    var onPushActionReturnValue: Bool!
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     The closure has first priority to return a value for the mocked function. If the closure returns `nil`,
     then the mock will attempt to return the value for `onPushActionReturnValue`
     */
    var onPushActionClosure: ((PushNotificationAction) -> Bool)?

    /// Mocked function for `onPushAction(_ push: PushNotificationAction)`. Your opportunity to return a mocked value and check result of mock in test code.
    func onPushAction(_ push: PushNotificationAction) -> Bool {
        mockCalled = true
        onPushActionCallsCount += 1
        onPushActionReceivedArguments = push
        onPushActionReceivedInvocations.append(push)
        return onPushActionClosure.map { $0(push) } ?? onPushActionReturnValue
    }

    // MARK: - shouldDisplayPushAppInForeground

    /// Number of times the function was called.
    private(set) var shouldDisplayPushAppInForegroundCallsCount = 0
    /// `true` if the function was ever called.
    var shouldDisplayPushAppInForegroundCalled: Bool {
        shouldDisplayPushAppInForegroundCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    private(set) var shouldDisplayPushAppInForegroundReceivedArguments: PushNotification?
    /// Arguments from *all* of the times that the function was called.
    private(set) var shouldDisplayPushAppInForegroundReceivedInvocations: [PushNotification] = []
    /// Value to return from the mocked function.
    var shouldDisplayPushAppInForegroundReturnValue: Bool?
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     The closure has first priority to return a value for the mocked function. If the closure returns `nil`,
     then the mock will attempt to return the value for `shouldDisplayPushAppInForegroundReturnValue`
     */
    var shouldDisplayPushAppInForegroundClosure: ((PushNotification) -> Bool?)?

    /// Mocked function for `shouldDisplayPushAppInForeground(_ push: PushNotification)`. Your opportunity to return a mocked value and check result of mock in test code.
    func shouldDisplayPushAppInForeground(_ push: PushNotification) -> Bool? {
        mockCalled = true
        shouldDisplayPushAppInForegroundCallsCount += 1
        shouldDisplayPushAppInForegroundReceivedArguments = push
        shouldDisplayPushAppInForegroundReceivedInvocations.append(push)
        return shouldDisplayPushAppInForegroundClosure.map { $0(push) } ?? shouldDisplayPushAppInForegroundReturnValue
    }

    // MARK: - newNotificationCenterDelegateSet

    /// Number of times the function was called.
    private(set) var newNotificationCenterDelegateSetCallsCount = 0
    /// `true` if the function was ever called.
    var newNotificationCenterDelegateSetCalled: Bool {
        newNotificationCenterDelegateSetCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    private(set) var newNotificationCenterDelegateSetReceivedArguments: UNUserNotificationCenterDelegate??
    /// Arguments from *all* of the times that the function was called.
    private(set) var newNotificationCenterDelegateSetReceivedInvocations: [UNUserNotificationCenterDelegate?] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    var newNotificationCenterDelegateSetClosure: ((UNUserNotificationCenterDelegate?) -> Void)?

    /// Mocked function for `newNotificationCenterDelegateSet(_ newDelegate: UNUserNotificationCenterDelegate?)`. Your opportunity to return a mocked value and check result of mock in test code.
    func newNotificationCenterDelegateSet(_ newDelegate: UNUserNotificationCenterDelegate?) {
        mockCalled = true
        newNotificationCenterDelegateSetCallsCount += 1
        newNotificationCenterDelegateSetReceivedArguments = newDelegate
        newNotificationCenterDelegateSetReceivedInvocations.append(newDelegate)
        newNotificationCenterDelegateSetClosure?(newDelegate)
    }

    // MARK: - beginListening

    /// Number of times the function was called.
    private(set) var beginListeningCallsCount = 0
    /// `true` if the function was ever called.
    var beginListeningCalled: Bool {
        beginListeningCallsCount > 0
    }

    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    var beginListeningClosure: (() -> Void)?

    /// Mocked function for `beginListening()`. Your opportunity to return a mocked value and check result of mock in test code.
    func beginListening() {
        mockCalled = true
        beginListeningCallsCount += 1
        beginListeningClosure?()
    }
}

/**
 Class to easily create a mocked version of the `PushHistory` class.
 This class is equipped with functions and properties ready for you to mock!

 Note: This file is automatically generated. This means the mocks should always be up-to-date and has a consistent API.
 See the SDK documentation to learn the basics behind using the mock classes in the SDK.
 */
class PushHistoryMock: PushHistory, Mock {
    /// If *any* interactions done on mock. `true` if any method or property getter/setter called.
    var mockCalled: Bool = false //

    init() {
        Mocks.shared.add(mock: self)
    }

    public func resetMock() {
        hasHandledPushCallsCount = 0
        hasHandledPushReceivedArguments = nil
        hasHandledPushReceivedInvocations = []

        mockCalled = false // do last as resetting properties above can make this true
    }

    // MARK: - hasHandledPush

    /// Number of times the function was called.
    private(set) var hasHandledPushCallsCount = 0
    /// `true` if the function was ever called.
    var hasHandledPushCalled: Bool {
        hasHandledPushCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    private(set) var hasHandledPushReceivedArguments: (pushEvent: PushHistoryEvent, pushId: String, pushDeliveryDate: Date)?
    /// Arguments from *all* of the times that the function was called.
    private(set) var hasHandledPushReceivedInvocations: [(pushEvent: PushHistoryEvent, pushId: String, pushDeliveryDate: Date)] = []
    /// Value to return from the mocked function.
    var hasHandledPushReturnValue: Bool!
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     The closure has first priority to return a value for the mocked function. If the closure returns `nil`,
     then the mock will attempt to return the value for `hasHandledPushReturnValue`
     */
    var hasHandledPushClosure: ((PushHistoryEvent, String, Date) -> Bool)?

    /// Mocked function for `hasHandledPush(pushEvent: PushHistoryEvent, pushId: String, pushDeliveryDate: Date)`. Your opportunity to return a mocked value and check result of mock in test code.
    func hasHandledPush(pushEvent: PushHistoryEvent, pushId: String, pushDeliveryDate: Date) -> Bool {
        mockCalled = true
        hasHandledPushCallsCount += 1
        hasHandledPushReceivedArguments = (pushEvent: pushEvent, pushId: pushId, pushDeliveryDate: pushDeliveryDate)
        hasHandledPushReceivedInvocations.append((pushEvent: pushEvent, pushId: pushId, pushDeliveryDate: pushDeliveryDate))
        return hasHandledPushClosure.map { $0(pushEvent, pushId, pushDeliveryDate) } ?? hasHandledPushReturnValue
    }
}

/**
 Class to easily create a mocked version of the `UserNotificationCenter` class.
 This class is equipped with functions and properties ready for you to mock!

 Note: This file is automatically generated. This means the mocks should always be up-to-date and has a consistent API.
 See the SDK documentation to learn the basics behind using the mock classes in the SDK.
 */
class UserNotificationCenterMock: UserNotificationCenter, Mock {
    /// If *any* interactions done on mock. `true` if any method or property getter/setter called.
    var mockCalled: Bool = false //

    init() {
        Mocks.shared.add(mock: self)
    }

    /**
     When setter of the property called, the value given to setter is set here.
     When the getter of the property called, the value set here will be returned. Your chance to mock the property.
     */
    var underlyingCurrentDelegate: UNUserNotificationCenterDelegate? = nil
    /// `true` if the getter or setter of property is called at least once.
    var currentDelegateCalled: Bool {
        currentDelegateGetCalled || currentDelegateSetCalled
    }

    /// `true` if the getter called on the property at least once.
    var currentDelegateGetCalled: Bool {
        currentDelegateGetCallsCount > 0
    }

    var currentDelegateGetCallsCount = 0
    /// `true` if the setter called on the property at least once.
    var currentDelegateSetCalled: Bool {
        currentDelegateSetCallsCount > 0
    }

    var currentDelegateSetCallsCount = 0
    /// The mocked property with a getter and setter.
    var currentDelegate: UNUserNotificationCenterDelegate? {
        get {
            mockCalled = true
            currentDelegateGetCallsCount += 1
            return underlyingCurrentDelegate
        }
        set(value) {
            mockCalled = true
            currentDelegateSetCallsCount += 1
            underlyingCurrentDelegate = value
        }
    }

    public func resetMock() {
        currentDelegate = nil
        currentDelegateGetCallsCount = 0
        currentDelegateSetCallsCount = 0
    }
}

// swiftlint:enable all
