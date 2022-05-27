// Generated using Sourcery 1.6.1 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT
// swiftlint:disable all

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif
import CioTracking
import Common
import Gist

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

internal class MessagingInAppMocks {
    internal static var shared: MessagingInAppMocks = .init()

    internal var mocks: [MessagingInAppMock] = []
    private init() {}

    func add(mock: MessagingInAppMock) {
        mocks.append(mock)
    }

    func resetAll() {
        mocks.forEach {
            $0.resetMock()
        }
    }
}

internal protocol MessagingInAppMock {
    func resetMock()
}

/**
 Class to easily create a mocked version of the `InAppProvider` class.
 This class is equipped with functions and properties ready for you to mock!

 Note: This file is automatically generated. This means the mocks should always be up-to-date and has a consistent API.
 See the SDK documentation to learn the basics behind using the mock classes in the SDK.
 */
internal class InAppProviderMock: InAppProvider, MessagingInAppMock {
    /// If *any* interactions done on mock. `true` if any method or property getter/setter called.
    internal var mockCalled: Bool = false //

    internal init() {
        MessagingInAppMocks.shared.add(mock: self)
    }

    internal func resetMock() {
        initializeCallsCount = 0
        initializeReceivedArguments = nil
        initializeReceivedInvocations = []

        mockCalled = false // do last as resetting properties above can make this true
        setProfileIdentifierCallsCount = 0
        setProfileIdentifierReceivedArguments = nil
        setProfileIdentifierReceivedInvocations = []

        mockCalled = false // do last as resetting properties above can make this true
        clearIdentifyCallsCount = 0

        mockCalled = false // do last as resetting properties above can make this true
    }

    // MARK: - initialize

    /// Number of times the function was called.
    internal private(set) var initializeCallsCount = 0
    /// `true` if the function was ever called.
    internal var initializeCalled: Bool {
        initializeCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    internal private(set) var initializeReceivedArguments: (id: String, delegate: GistDelegate)?
    /// Arguments from *all* of the times that the function was called.
    internal private(set) var initializeReceivedInvocations: [(id: String, delegate: GistDelegate)] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    internal var initializeClosure: ((String, GistDelegate) -> Void)?

    /// Mocked function for `initialize(id: String, delegate: GistDelegate)`. Your opportunity to return a mocked value and check result of mock in test code.
    internal func initialize(id: String, delegate: GistDelegate) {
        mockCalled = true
        initializeCallsCount += 1
        initializeReceivedArguments = (id: id, delegate: delegate)
        initializeReceivedInvocations.append((id: id, delegate: delegate))
        initializeClosure?(id, delegate)
    }

    // MARK: - setProfileIdentifier

    /// Number of times the function was called.
    internal private(set) var setProfileIdentifierCallsCount = 0
    /// `true` if the function was ever called.
    internal var setProfileIdentifierCalled: Bool {
        setProfileIdentifierCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    internal private(set) var setProfileIdentifierReceivedArguments: String?
    /// Arguments from *all* of the times that the function was called.
    internal private(set) var setProfileIdentifierReceivedInvocations: [String] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    internal var setProfileIdentifierClosure: ((String) -> Void)?

    /// Mocked function for `setProfileIdentifier(_ id: String)`. Your opportunity to return a mocked value and check result of mock in test code.
    internal func setProfileIdentifier(_ id: String) {
        mockCalled = true
        setProfileIdentifierCallsCount += 1
        setProfileIdentifierReceivedArguments = id
        setProfileIdentifierReceivedInvocations.append(id)
        setProfileIdentifierClosure?(id)
    }

    // MARK: - clearIdentify

    /// Number of times the function was called.
    internal private(set) var clearIdentifyCallsCount = 0
    /// `true` if the function was ever called.
    internal var clearIdentifyCalled: Bool {
        clearIdentifyCallsCount > 0
    }

    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    internal var clearIdentifyClosure: (() -> Void)?

    /// Mocked function for `clearIdentify()`. Your opportunity to return a mocked value and check result of mock in test code.
    internal func clearIdentify() {
        mockCalled = true
        clearIdentifyCallsCount += 1
        clearIdentifyClosure?()
    }
}

/**
 Class to easily create a mocked version of the `MessagingInAppInstance` class.
 This class is equipped with functions and properties ready for you to mock!

 Note: This file is automatically generated. This means the mocks should always be up-to-date and has a consistent API.
 See the SDK documentation to learn the basics behind using the mock classes in the SDK.
 */
public class MessagingInAppInstanceMock: MessagingInAppInstance, MessagingInAppMock {
    /// If *any* interactions done on mock. `true` if any method or property getter/setter called.
    public var mockCalled: Bool = false //

    public init() {
        MessagingInAppMocks.shared.add(mock: self)
    }

    internal func resetMock() {
        initializeCallsCount = 0
        initializeReceivedArguments = nil
        initializeReceivedInvocations = []

        mockCalled = false // do last as resetting properties above can make this true
    }

    // MARK: - initialize

    /// Number of times the function was called.
    public private(set) var initializeCallsCount = 0
    /// `true` if the function was ever called.
    public var initializeCalled: Bool {
        initializeCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var initializeReceivedArguments: String?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var initializeReceivedInvocations: [String] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var initializeClosure: ((String) -> Void)?

    /// Mocked function for `initialize(organizationId: String)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func initialize(organizationId: String) {
        mockCalled = true
        initializeCallsCount += 1
        initializeReceivedArguments = organizationId
        initializeReceivedInvocations.append(organizationId)
        initializeClosure?(organizationId)
    }
}
