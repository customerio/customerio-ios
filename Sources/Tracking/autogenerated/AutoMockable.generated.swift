// Generated using Sourcery 1.5.0 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT
// swiftlint:disable all

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Common

/**
 ######################################################
 Documentation
 ######################################################

 This automatically generated file you are viewing contains mock classes that you can use in your test suite.

 * How do you generate a new mock class?

 1. Mocks are generated from Swift protocols. So, you must make one.

 ```
 protocol FriendsRepository {
     func acceptFriendRequest(_ onComplete: @escaping () -> Void)
 }

 class AppFriendsRepository: FriendsRepository {
     ...
 }
 ```

 2. Have your new protocol extend `AutoMockable`:

 ```
 protocol FriendsRepository: AutoMockable {
 ```

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
 Class to easily create a mocked version of the `IdentifyRepository` class.
 This class is equipped with functions and properties ready for you to mock!

 Note: This file is automatically generated. This means the mocks should always be up-to-date and has a consistent API.
 See the SDK documentation to learn the basics behind using the mock classes in the SDK.
 */
internal class IdentifyRepositoryMock: IdentifyRepository {
    /// If *any* interactions done on mock. `true` if any method or property getter/setter called.
    internal var mockCalled: Bool = false //

    // MARK: - addOrUpdateCustomer

    /// Number of times the function was called.
    internal var addOrUpdateCustomerCallsCount = 0
    /// `true` if the function was ever called.
    internal var addOrUpdateCustomerCalled: Bool {
        addOrUpdateCustomerCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    internal var addOrUpdateCustomerReceivedArguments: (identifier: String, email: String?,
                                                        onComplete: (Result<Void, CustomerIOError>) -> Void)?
    /// Arguments from *all* of the times that the function was called.
    internal var addOrUpdateCustomerReceivedInvocations: [(identifier: String, email: String?,
                                                           onComplete: (Result<Void, CustomerIOError>) -> Void)] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    internal var addOrUpdateCustomerClosure: ((String, String?, @escaping (Result<Void, CustomerIOError>) -> Void)
        -> Void)?

    /// Mocked function for `addOrUpdateCustomer(identifier: String, email: String?, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void)`. Your opportunity to return a mocked value and check result of mock in test code.
    internal func addOrUpdateCustomer(
        identifier: String,
        email: String?,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        mockCalled = true
        addOrUpdateCustomerCallsCount += 1
        addOrUpdateCustomerReceivedArguments = (identifier: identifier, email: email, onComplete: onComplete)
        addOrUpdateCustomerReceivedInvocations.append((identifier: identifier, email: email, onComplete: onComplete))
        addOrUpdateCustomerClosure?(identifier, email, onComplete)
    }

    // MARK: - removeCustomer

    /// Number of times the function was called.
    internal var removeCustomerCallsCount = 0
    /// `true` if the function was ever called.
    internal var removeCustomerCalled: Bool {
        removeCustomerCallsCount > 0
    }

    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    internal var removeCustomerClosure: (() -> Void)?

    /// Mocked function for `removeCustomer()`. Your opportunity to return a mocked value and check result of mock in test code.
    internal func removeCustomer() {
        mockCalled = true
        removeCustomerCallsCount += 1
        removeCustomerClosure?()
    }
}
