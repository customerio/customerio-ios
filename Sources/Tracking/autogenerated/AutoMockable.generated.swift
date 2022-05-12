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

internal class TrackingMocks {
    internal static var shared: TrackingMocks = .init()

    internal var mocks: [TrackingMock] = []
    private init() {}

    func add(mock: TrackingMock) {
        mocks.append(mock)
    }

    func resetAll() {
        mocks.forEach {
            $0.resetMock()
        }
    }
}

internal protocol TrackingMock {
    func resetMock()
}

/**
 Class to easily create a mocked version of the `CustomerIOInstance` class.
 This class is equipped with functions and properties ready for you to mock!

 Note: This file is automatically generated. This means the mocks should always be up-to-date and has a consistent API.
 See the SDK documentation to learn the basics behind using the mock classes in the SDK.
 */
public class CustomerIOInstanceMock: CustomerIOInstance, TrackingMock {
    /// If *any* interactions done on mock. `true` if any method or property getter/setter called.
    public var mockCalled: Bool = false //

    public init() {
        TrackingMocks.shared.add(mock: self)
    }

    /**
     When setter of the property called, the value given to setter is set here.
     When the getter of the property called, the value set here will be returned. Your chance to mock the property.
     */
    public var underlyingSiteId: String?
    /// `true` if the getter or setter of property is called at least once.
    public var siteIdCalled: Bool {
        siteIdGetCalled || siteIdSetCalled
    }

    /// `true` if the getter called on the property at least once.
    public var siteIdGetCalled: Bool {
        siteIdGetCallsCount > 0
    }

    public var siteIdGetCallsCount = 0
    /// `true` if the setter called on the property at least once.
    public var siteIdSetCalled: Bool {
        siteIdSetCallsCount > 0
    }

    public var siteIdSetCallsCount = 0
    /// The mocked property with a getter and setter.
    public var siteId: String? {
        get {
            mockCalled = true
            siteIdGetCallsCount += 1
            return underlyingSiteId
        }
        set(value) {
            mockCalled = true
            siteIdSetCallsCount += 1
            underlyingSiteId = value
        }
    }

    /**
     When setter of the property called, the value given to setter is set here.
     When the getter of the property called, the value set here will be returned. Your chance to mock the property.
     */
    public var underlyingProfileAttributes: [String: Any] = [:]
    /// `true` if the getter or setter of property is called at least once.
    public var profileAttributesCalled: Bool {
        profileAttributesGetCalled || profileAttributesSetCalled
    }

    /// `true` if the getter called on the property at least once.
    public var profileAttributesGetCalled: Bool {
        profileAttributesGetCallsCount > 0
    }

    public var profileAttributesGetCallsCount = 0
    /// `true` if the setter called on the property at least once.
    public var profileAttributesSetCalled: Bool {
        profileAttributesSetCallsCount > 0
    }

    public var profileAttributesSetCallsCount = 0
    /// The mocked property with a getter and setter.
    public var profileAttributes: [String: Any] {
        get {
            mockCalled = true
            profileAttributesGetCallsCount += 1
            return underlyingProfileAttributes
        }
        set(value) {
            mockCalled = true
            profileAttributesSetCallsCount += 1
            underlyingProfileAttributes = value
        }
    }

    /**
     When setter of the property called, the value given to setter is set here.
     When the getter of the property called, the value set here will be returned. Your chance to mock the property.
     */
    public var underlyingDeviceAttributes: [String: Any] = [:]
    /// `true` if the getter or setter of property is called at least once.
    public var deviceAttributesCalled: Bool {
        deviceAttributesGetCalled || deviceAttributesSetCalled
    }

    /// `true` if the getter called on the property at least once.
    public var deviceAttributesGetCalled: Bool {
        deviceAttributesGetCallsCount > 0
    }

    public var deviceAttributesGetCallsCount = 0
    /// `true` if the setter called on the property at least once.
    public var deviceAttributesSetCalled: Bool {
        deviceAttributesSetCallsCount > 0
    }

    public var deviceAttributesSetCallsCount = 0
    /// The mocked property with a getter and setter.
    public var deviceAttributes: [String: Any] {
        get {
            mockCalled = true
            deviceAttributesGetCallsCount += 1
            return underlyingDeviceAttributes
        }
        set(value) {
            mockCalled = true
            deviceAttributesSetCallsCount += 1
            underlyingDeviceAttributes = value
        }
    }

    internal func resetMock() {
        siteId = nil
        siteIdGetCallsCount = 0
        siteIdSetCallsCount = 0
        profileAttributesGetCallsCount = 0
        profileAttributesSetCallsCount = 0
        deviceAttributesGetCallsCount = 0
        deviceAttributesSetCallsCount = 0
        identifyCallsCount = 0
        identifyReceivedArguments = nil
        identifyReceivedInvocations = []

        mockCalled = false // do last as resetting properties above can make this true
        identifyEncodableReceivedArguments = nil
        identifyEncodableReceivedInvocations = []

        mockCalled = false // do last as resetting properties above can make this true
        clearIdentifyCallsCount = 0

        mockCalled = false // do last as resetting properties above can make this true
        trackCallsCount = 0
        trackReceivedArguments = nil
        trackReceivedInvocations = []

        mockCalled = false // do last as resetting properties above can make this true
        trackEncodableReceivedArguments = nil
        trackEncodableReceivedInvocations = []

        mockCalled = false // do last as resetting properties above can make this true
        screenCallsCount = 0
        screenReceivedArguments = nil
        screenReceivedInvocations = []

        mockCalled = false // do last as resetting properties above can make this true
        screenEncodableReceivedArguments = nil
        screenEncodableReceivedInvocations = []

        mockCalled = false // do last as resetting properties above can make this true
        configCallsCount = 0
        configReceivedArguments = nil
        configReceivedInvocations = []

        mockCalled = false // do last as resetting properties above can make this true
    }

    // MARK: - identify

    /// Number of times the function was called.
    public private(set) var identifyCallsCount = 0
    /// `true` if the function was ever called.
    public var identifyCalled: Bool {
        identifyCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var identifyReceivedArguments: (identifier: String, body: [String: Any])?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var identifyReceivedInvocations: [(identifier: String, body: [String: Any])] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var identifyClosure: ((String, [String: Any]) -> Void)?

    /// Mocked function for `identify(identifier: String, body: [String: Any])`. Your opportunity to return a mocked value and check result of mock in test code.
    public func identify(identifier: String, body: [String: Any]) {
        mockCalled = true
        identifyCallsCount += 1
        identifyReceivedArguments = (identifier: identifier, body: body)
        identifyReceivedInvocations.append((identifier: identifier, body: body))
        identifyClosure?(identifier, body)
    }

    // MARK: - identify<RequestBody: Encodable>

    /// The arguments from the *last* time the function was called.
    public private(set) var identifyEncodableReceivedArguments: (identifier: String, body: AnyEncodable)?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var identifyEncodableReceivedInvocations: [(identifier: String, body: AnyEncodable)] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var identifyEncodableClosure: ((String, AnyEncodable) -> Void)?

    /// Mocked function for `identify<RequestBody: Encodable>(identifier: String, body: RequestBody)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func identify<RequestBody: Encodable>(identifier: String, body: RequestBody) {
        mockCalled = true
        identifyCallsCount += 1
        identifyEncodableReceivedArguments = (identifier: identifier, body: AnyEncodable(body))
        identifyEncodableReceivedInvocations.append((identifier: identifier, body: AnyEncodable(body)))
        identifyEncodableClosure?(identifier, AnyEncodable(body))
    }

    // MARK: - clearIdentify

    /// Number of times the function was called.
    public private(set) var clearIdentifyCallsCount = 0
    /// `true` if the function was ever called.
    public var clearIdentifyCalled: Bool {
        clearIdentifyCallsCount > 0
    }

    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var clearIdentifyClosure: (() -> Void)?

    /// Mocked function for `clearIdentify()`. Your opportunity to return a mocked value and check result of mock in test code.
    public func clearIdentify() {
        mockCalled = true
        clearIdentifyCallsCount += 1
        clearIdentifyClosure?()
    }

    // MARK: - track

    /// Number of times the function was called.
    public private(set) var trackCallsCount = 0
    /// `true` if the function was ever called.
    public var trackCalled: Bool {
        trackCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var trackReceivedArguments: (name: String, data: [String: Any])?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var trackReceivedInvocations: [(name: String, data: [String: Any])] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var trackClosure: ((String, [String: Any]) -> Void)?

    /// Mocked function for `track(name: String, data: [String: Any])`. Your opportunity to return a mocked value and check result of mock in test code.
    public func track(name: String, data: [String: Any]) {
        mockCalled = true
        trackCallsCount += 1
        trackReceivedArguments = (name: name, data: data)
        trackReceivedInvocations.append((name: name, data: data))
        trackClosure?(name, data)
    }

    // MARK: - track<RequestBody: Encodable>

    /// The arguments from the *last* time the function was called.
    public private(set) var trackEncodableReceivedArguments: (name: String, data: AnyEncodable)?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var trackEncodableReceivedInvocations: [(name: String, data: AnyEncodable)] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var trackEncodableClosure: ((String, AnyEncodable) -> Void)?

    /// Mocked function for `track<RequestBody: Encodable>(name: String, data: RequestBody?)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func track<RequestBody: Encodable>(name: String, data: RequestBody?) {
        mockCalled = true
        trackCallsCount += 1
        trackEncodableReceivedArguments = (name: name, data: AnyEncodable(data))
        trackEncodableReceivedInvocations.append((name: name, data: AnyEncodable(data)))
        trackEncodableClosure?(name, AnyEncodable(data))
    }

    // MARK: - screen

    /// Number of times the function was called.
    public private(set) var screenCallsCount = 0
    /// `true` if the function was ever called.
    public var screenCalled: Bool {
        screenCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var screenReceivedArguments: (name: String, data: [String: Any])?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var screenReceivedInvocations: [(name: String, data: [String: Any])] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var screenClosure: ((String, [String: Any]) -> Void)?

    /// Mocked function for `screen(name: String, data: [String: Any])`. Your opportunity to return a mocked value and check result of mock in test code.
    public func screen(name: String, data: [String: Any]) {
        mockCalled = true
        screenCallsCount += 1
        screenReceivedArguments = (name: name, data: data)
        screenReceivedInvocations.append((name: name, data: data))
        screenClosure?(name, data)
    }

    // MARK: - screen<RequestBody: Encodable>

    /// The arguments from the *last* time the function was called.
    public private(set) var screenEncodableReceivedArguments: (name: String, data: AnyEncodable)?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var screenEncodableReceivedInvocations: [(name: String, data: AnyEncodable)] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var screenEncodableClosure: ((String, AnyEncodable) -> Void)?

    /// Mocked function for `screen<RequestBody: Encodable>(name: String, data: RequestBody?)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func screen<RequestBody: Encodable>(name: String, data: RequestBody?) {
        mockCalled = true
        screenCallsCount += 1
        screenEncodableReceivedArguments = (name: name, data: AnyEncodable(data))
        screenEncodableReceivedInvocations.append((name: name, data: AnyEncodable(data)))
        screenEncodableClosure?(name, AnyEncodable(data))
    }

    // MARK: - config

    /// Number of times the function was called.
    public private(set) var configCallsCount = 0
    /// `true` if the function was ever called.
    public var configCalled: Bool {
        configCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var configReceivedArguments: ()?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var configReceivedInvocations: [()] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var configClosure: (((inout SdkConfig) -> Void) -> Void)?

    /// Mocked function for `config(_ handler: (inout SdkConfig) -> Void)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func config(_ handler: (inout SdkConfig) -> Void) {
        mockCalled = true
        configCallsCount += 1
        configReceivedArguments = ()
        configReceivedInvocations.append(())
        configClosure?(handler)
    }
}
