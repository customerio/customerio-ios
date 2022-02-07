// Generated using Sourcery 1.6.1 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT
// swiftlint:disable all

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
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
    public static var shared: MessagingPushFCMMocks = .init()

    public var mocks: [MessagingPushFCMMock] = []
    private init() {}

    func add(mock: MessagingPushFCMMock) {
        mocks.append(mock)
    }

    func resetAll() {
        mocks.forEach {
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
        mockCalled = false

        didReceiveRegistrationTokenCallsCount = 0
        didReceiveRegistrationTokenReceivedArguments = nil
        didReceiveRegistrationTokenReceivedInvocations = []
        didFailToRegisterForRemoteNotificationsCallsCount = 0
        didFailToRegisterForRemoteNotificationsReceivedArguments = nil
        didFailToRegisterForRemoteNotificationsReceivedInvocations = []
    }

    // MARK: - messaging

    /// Number of times the function was called.
    public private(set) var didReceiveRegistrationTokenCallsCount = 0
    /// `true` if the function was ever called.
    public var didReceiveRegistrationTokenCalled: Bool {
        didReceiveRegistrationTokenCallsCount > 0
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
        mockCalled = true
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
        didFailToRegisterForRemoteNotificationsCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var didFailToRegisterForRemoteNotificationsReceivedArguments: (application: Any, error: Error)?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var didFailToRegisterForRemoteNotificationsReceivedInvocations: [(application: Any,
                                                                                          error: Error)] = []
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
