// Generated using Sourcery 1.5.0 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT
// swiftlint:disable all

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
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
 Class to easily create a mocked version of the `MessagingPushInstance` class.
 This class is equipped with functions and properties ready for you to mock!

 Note: This file is automatically generated. This means the mocks should always be up-to-date and has a consistent API.
 See the SDK documentation to learn the basics behind using the mock classes in the SDK.
 */
public class MessagingPushInstanceMock: MessagingPushInstance {
    /// If *any* interactions done on mock. `true` if any method or property getter/setter called.
    public var mockCalled: Bool = false //

    // MARK: - registerDeviceToken

    /// Number of times the function was called.
    public private(set) var registerDeviceTokenCallsCount = 0
    /// `true` if the function was ever called.
    public var registerDeviceTokenCalled: Bool {
        registerDeviceTokenCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var registerDeviceTokenReceivedArguments: (deviceToken: String,
                                                                   onComplete: (Result<Void, CustomerIOError>) -> Void)?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var registerDeviceTokenReceivedInvocations: [(deviceToken: String,
                                                                      onComplete: (Result<Void, CustomerIOError>)
                                                                          -> Void)] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var registerDeviceTokenClosure: ((String, (Result<Void, CustomerIOError>) -> Void) -> Void)?

    /// Mocked function for `registerDeviceToken(_ deviceToken: String, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func registerDeviceToken(
        _ deviceToken: String,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        mockCalled = true
        registerDeviceTokenCallsCount += 1
        registerDeviceTokenReceivedArguments = (deviceToken: deviceToken, onComplete: onComplete)
        registerDeviceTokenReceivedInvocations.append((deviceToken: deviceToken, onComplete: onComplete))
        registerDeviceTokenClosure?(deviceToken, onComplete)
    }

    // MARK: - deleteDeviceToken

    /// Number of times the function was called.
    public private(set) var deleteDeviceTokenCallsCount = 0
    /// `true` if the function was ever called.
    public var deleteDeviceTokenCalled: Bool {
        deleteDeviceTokenCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var deleteDeviceTokenReceivedArguments: ((Result<Void, CustomerIOError>) -> Void)?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var deleteDeviceTokenReceivedInvocations: [(Result<Void, CustomerIOError>) -> Void] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var deleteDeviceTokenClosure: (((Result<Void, CustomerIOError>) -> Void) -> Void)?

    /// Mocked function for `deleteDeviceToken(onComplete: @escaping (Result<Void, CustomerIOError>) -> Void)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func deleteDeviceToken(onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) {
        mockCalled = true
        deleteDeviceTokenCallsCount += 1
        deleteDeviceTokenReceivedArguments = onComplete
        deleteDeviceTokenReceivedInvocations.append(onComplete)
        deleteDeviceTokenClosure?(onComplete)
    }

    // MARK: - trackMetric

    /// Number of times the function was called.
    public private(set) var trackMetricCallsCount = 0
    /// `true` if the function was ever called.
    public var trackMetricCalled: Bool {
        trackMetricCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var trackMetricReceivedArguments: (deliveryID: String, event: Metric, deviceToken: String,
                                                           onComplete: (Result<Void, CustomerIOError>) -> Void)?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var trackMetricReceivedInvocations: [(deliveryID: String, event: Metric, deviceToken: String,
                                                              onComplete: (Result<Void, CustomerIOError>) -> Void)] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var trackMetricClosure: ((String, Metric, String, (Result<Void, CustomerIOError>) -> Void) -> Void)?

    /// Mocked function for `trackMetric(deliveryID: String, event: Metric, deviceToken: String, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func trackMetric(
        deliveryID: String,
        event: Metric,
        deviceToken: String,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        mockCalled = true
        trackMetricCallsCount += 1
        trackMetricReceivedArguments = (deliveryID: deliveryID, event: event, deviceToken: deviceToken,
                                        onComplete: onComplete)
        trackMetricReceivedInvocations
            .append((deliveryID: deliveryID, event: event, deviceToken: deviceToken, onComplete: onComplete))
        trackMetricClosure?(deliveryID, event, deviceToken, onComplete)
    }
}
