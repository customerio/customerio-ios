// Generated using Sourcery 1.5.0 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT
// swiftlint:disable all

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
 Class to easily create a mocked version of the `CustomerIOInstance` class.
 This class is equipped with functions and properties ready for you to mock!

 Note: This file is automatically generated. This means the mocks should always be up-to-date and has a consistent API.
 See the SDK documentation to learn the basics behind using the mock classes in the SDK.
 */
public class CustomerIOInstanceMock: CustomerIOInstance {
    /// If *any* interactions done on mock. `true` if any method or property getter/setter called.
    public var mockCalled: Bool = false //

    // MARK: - identify<RequestBody: Encodable>

    /// Number of times the function was called.
    public private(set) var identifyBodyCallsCount = 0
    /// `true` if the function was ever called.
    public var identifyBodyCalled: Bool {
        identifyBodyCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var identifyBodyReceivedArguments: (identifier: String, body: AnyEncodable,
                                                            onComplete: (Result<Void, CustomerIOError>) -> Void,
                                                            jsonEncoder: JSONEncoder?)?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var identifyBodyReceivedInvocations: [(identifier: String, body: AnyEncodable,
                                                               onComplete: (Result<Void, CustomerIOError>) -> Void,
                                                               jsonEncoder: JSONEncoder?)] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var identifyBodyClosure: ((String, AnyEncodable, (Result<Void, CustomerIOError>) -> Void, JSONEncoder?)
        -> Void)?

    /// Mocked function for `identify<RequestBody: Encodable>(identifier: String, body: RequestBody, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void, jsonEncoder: JSONEncoder?)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func identify<RequestBody: Encodable>(
        identifier: String,
        body: RequestBody,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void,
        jsonEncoder: JSONEncoder?
    ) {
        mockCalled = true
        identifyBodyCallsCount += 1
        identifyBodyReceivedArguments = (identifier: identifier, body: AnyEncodable(body), onComplete: onComplete,
                                         jsonEncoder: jsonEncoder)
        identifyBodyReceivedInvocations
            .append((identifier: identifier, body: AnyEncodable(body), onComplete: onComplete,
                     jsonEncoder: jsonEncoder))
        identifyBodyClosure?(identifier, AnyEncodable(body), onComplete, jsonEncoder)
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
}

/**
 Class to easily create a mocked version of the `EventBus` class.
 This class is equipped with functions and properties ready for you to mock!

 Note: This file is automatically generated. This means the mocks should always be up-to-date and has a consistent API.
 See the SDK documentation to learn the basics behind using the mock classes in the SDK.
 */
public class EventBusMock: EventBus {
    /// If *any* interactions done on mock. `true` if any method or property getter/setter called.
    public var mockCalled: Bool = false //

    // MARK: - post

    /// Number of times the function was called.
    public private(set) var postCallsCount = 0
    /// `true` if the function was ever called.
    public var postCalled: Bool {
        postCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var postReceivedArguments: (EventBusEvent)?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var postReceivedInvocations: [EventBusEvent] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var postClosure: ((EventBusEvent) -> Void)?

    /// Mocked function for `post(_ event: EventBusEvent)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func post(_ event: EventBusEvent) {
        mockCalled = true
        postCallsCount += 1
        postReceivedArguments = event
        postReceivedInvocations.append(event)
        postClosure?(event)
    }

    // MARK: - register

    /// Number of times the function was called.
    public private(set) var registerCallsCount = 0
    /// `true` if the function was ever called.
    public var registerCalled: Bool {
        registerCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var registerReceivedArguments: (listener: EventBusEventListener, event: EventBusEvent)?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var registerReceivedInvocations: [(listener: EventBusEventListener, event: EventBusEvent)] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var registerClosure: ((EventBusEventListener, EventBusEvent) -> Void)?

    /// Mocked function for `register(_ listener: EventBusEventListener, event: EventBusEvent)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func register(_ listener: EventBusEventListener, event: EventBusEvent) {
        mockCalled = true
        registerCallsCount += 1
        registerReceivedArguments = (listener: listener, event: event)
        registerReceivedInvocations.append((listener: listener, event: event))
        registerClosure?(listener, event)
    }

    // MARK: - unregister

    /// Number of times the function was called.
    public private(set) var unregisterCallsCount = 0
    /// `true` if the function was ever called.
    public var unregisterCalled: Bool {
        unregisterCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var unregisterReceivedArguments: (EventBusEventListener)?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var unregisterReceivedInvocations: [EventBusEventListener] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var unregisterClosure: ((EventBusEventListener) -> Void)?

    /// Mocked function for `unregister(_ listener: EventBusEventListener)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func unregister(_ listener: EventBusEventListener) {
        mockCalled = true
        unregisterCallsCount += 1
        unregisterReceivedArguments = listener
        unregisterReceivedInvocations.append(listener)
        unregisterClosure?(listener)
    }
}

/**
 Class to easily create a mocked version of the `HttpClient` class.
 This class is equipped with functions and properties ready for you to mock!

 Note: This file is automatically generated. This means the mocks should always be up-to-date and has a consistent API.
 See the SDK documentation to learn the basics behind using the mock classes in the SDK.
 */
public class HttpClientMock: HttpClient {
    /// If *any* interactions done on mock. `true` if any method or property getter/setter called.
    public var mockCalled: Bool = false //

    // MARK: - request

    /// Number of times the function was called.
    public private(set) var requestCallsCount = 0
    /// `true` if the function was ever called.
    public var requestCalled: Bool {
        requestCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var requestReceivedArguments: (params: HttpRequestParams,
                                                       onComplete: (Result<Data, HttpRequestError>) -> Void)?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var requestReceivedInvocations: [(params: HttpRequestParams,
                                                          onComplete: (Result<Data, HttpRequestError>) -> Void)] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var requestClosure: ((HttpRequestParams, (Result<Data, HttpRequestError>) -> Void) -> Void)?

    /// Mocked function for `request(_ params: HttpRequestParams, onComplete: @escaping (Result<Data, HttpRequestError>) -> Void)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func request(_ params: HttpRequestParams, onComplete: @escaping (Result<Data, HttpRequestError>) -> Void) {
        mockCalled = true
        requestCallsCount += 1
        requestReceivedArguments = (params: params, onComplete: onComplete)
        requestReceivedInvocations.append((params: params, onComplete: onComplete))
        requestClosure?(params, onComplete)
    }
}

/**
 Class to easily create a mocked version of the `HttpRequestRunner` class.
 This class is equipped with functions and properties ready for you to mock!

 Note: This file is automatically generated. This means the mocks should always be up-to-date and has a consistent API.
 See the SDK documentation to learn the basics behind using the mock classes in the SDK.
 */
internal class HttpRequestRunnerMock: HttpRequestRunner {
    /// If *any* interactions done on mock. `true` if any method or property getter/setter called.
    internal var mockCalled: Bool = false //

    // MARK: - request

    /// Number of times the function was called.
    internal private(set) var requestCallsCount = 0
    /// `true` if the function was ever called.
    internal var requestCalled: Bool {
        requestCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    internal private(set) var requestReceivedArguments: (params: HttpRequestParams, httpBaseUrls: HttpBaseUrls,
                                                         onComplete: (Data?, HTTPURLResponse?, Error?) -> Void)?
    /// Arguments from *all* of the times that the function was called.
    internal private(set) var requestReceivedInvocations: [(params: HttpRequestParams, httpBaseUrls: HttpBaseUrls,
                                                            onComplete: (Data?, HTTPURLResponse?, Error?) -> Void)] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    internal var requestClosure: ((HttpRequestParams, HttpBaseUrls, (Data?, HTTPURLResponse?, Error?) -> Void) -> Void)?

    /// Mocked function for `request(_ params: HttpRequestParams, httpBaseUrls: HttpBaseUrls, onComplete: @escaping (Data?, HTTPURLResponse?, Error?) -> Void)`. Your opportunity to return a mocked value and check result of mock in test code.
    internal func request(
        _ params: HttpRequestParams,
        httpBaseUrls: HttpBaseUrls,
        onComplete: @escaping (Data?, HTTPURLResponse?, Error?) -> Void
    ) {
        mockCalled = true
        requestCallsCount += 1
        requestReceivedArguments = (params: params, httpBaseUrls: httpBaseUrls, onComplete: onComplete)
        requestReceivedInvocations.append((params: params, httpBaseUrls: httpBaseUrls, onComplete: onComplete))
        requestClosure?(params, httpBaseUrls, onComplete)
    }
}

/**
 Class to easily create a mocked version of the `IdentifyRepository` class.
 This class is equipped with functions and properties ready for you to mock!

 Note: This file is automatically generated. This means the mocks should always be up-to-date and has a consistent API.
 See the SDK documentation to learn the basics behind using the mock classes in the SDK.
 */
internal class IdentifyRepositoryMock: IdentifyRepository {
    /// If *any* interactions done on mock. `true` if any method or property getter/setter called.
    internal var mockCalled: Bool = false //

    internal var identifier: String?

    // MARK: - addOrUpdateCustomer<RequestBody: Encodable>

    /// Number of times the function was called.
    internal private(set) var addOrUpdateCustomerCallsCount = 0
    /// `true` if the function was ever called.
    internal var addOrUpdateCustomerCalled: Bool {
        addOrUpdateCustomerCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    internal private(set) var addOrUpdateCustomerReceivedArguments: (identifier: String, body: AnyEncodable,
                                                                     jsonEncoder: JSONEncoder?,
                                                                     onComplete: (Result<Void, CustomerIOError>)
                                                                         -> Void)?
    /// Arguments from *all* of the times that the function was called.
    internal private(set) var addOrUpdateCustomerReceivedInvocations: [(identifier: String, body: AnyEncodable,
                                                                        jsonEncoder: JSONEncoder?,
                                                                        onComplete: (Result<Void, CustomerIOError>)
                                                                            -> Void)] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    internal var addOrUpdateCustomerClosure: ((String, AnyEncodable, JSONEncoder?,
                                               (Result<Void, CustomerIOError>) -> Void) -> Void)?

    /// Mocked function for `addOrUpdateCustomer<RequestBody: Encodable>(identifier: String, body: RequestBody, jsonEncoder: JSONEncoder?, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void)`. Your opportunity to return a mocked value and check result of mock in test code.
    internal func addOrUpdateCustomer<RequestBody: Encodable>(
        identifier: String,
        body: RequestBody,
        jsonEncoder: JSONEncoder?,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        mockCalled = true
        addOrUpdateCustomerCallsCount += 1
        addOrUpdateCustomerReceivedArguments = (identifier: identifier, body: AnyEncodable(body),
                                                jsonEncoder: jsonEncoder, onComplete: onComplete)
        addOrUpdateCustomerReceivedInvocations
            .append((identifier: identifier, body: AnyEncodable(body), jsonEncoder: jsonEncoder,
                     onComplete: onComplete))
        addOrUpdateCustomerClosure?(identifier, AnyEncodable(body), jsonEncoder, onComplete)
    }

    // MARK: - removeCustomer

    /// Number of times the function was called.
    internal private(set) var removeCustomerCallsCount = 0
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

/**
 Class to easily create a mocked version of the `KeyValueStorage` class.
 This class is equipped with functions and properties ready for you to mock!

 Note: This file is automatically generated. This means the mocks should always be up-to-date and has a consistent API.
 See the SDK documentation to learn the basics behind using the mock classes in the SDK.
 */
public class KeyValueStorageMock: KeyValueStorage {
    /// If *any* interactions done on mock. `true` if any method or property getter/setter called.
    public var mockCalled: Bool = false //

    /**
     When setter of the property called, the value given to setter is set here.
     When the getter of the property called, the value set here will be returned. Your chance to mock the property.
     */
    public var underlyingSharedSiteId: String!
    /// `true` if the getter or setter of property is called at least once.
    public var sharedSiteIdCalled = false
    /// `true` if the getter called on the property at least once.
    public var sharedSiteIdGetCalled = false
    /// `true` if the setter called on the property at least once.
    public var sharedSiteIdSetCalled = false
    /// The mocked property with a getter and setter.
    public var sharedSiteId: String {
        get {
            mockCalled = true
            sharedSiteIdCalled = true
            sharedSiteIdGetCalled = true
            return underlyingSharedSiteId
        }
        set(value) {
            mockCalled = true
            sharedSiteIdCalled = true
            sharedSiteIdSetCalled = true
            underlyingSharedSiteId = value
        }
    }

    // MARK: - integer

    /// Number of times the function was called.
    public private(set) var integerCallsCount = 0
    /// `true` if the function was ever called.
    public var integerCalled: Bool {
        integerCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var integerReceivedArguments: (siteId: String, key: KeyValueStorageKey)?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var integerReceivedInvocations: [(siteId: String, key: KeyValueStorageKey)] = []
    /// Value to return from the mocked function.
    public var integerReturnValue: Int?
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     The closure has first priority to return a value for the mocked function. If the closure returns `nil`,
     then the mock will attempt to return the value for `integerReturnValue`
     */
    public var integerClosure: ((String, KeyValueStorageKey) -> Int?)?

    /// Mocked function for `integer(siteId: String, forKey key: KeyValueStorageKey)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func integer(siteId: String, forKey key: KeyValueStorageKey) -> Int? {
        mockCalled = true
        integerCallsCount += 1
        integerReceivedArguments = (siteId: siteId, key: key)
        integerReceivedInvocations.append((siteId: siteId, key: key))
        return integerClosure.map { $0(siteId, key) } ?? integerReturnValue
    }

    // MARK: - setInt

    /// Number of times the function was called.
    public private(set) var setIntCallsCount = 0
    /// `true` if the function was ever called.
    public var setIntCalled: Bool {
        setIntCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var setIntReceivedArguments: (siteId: String, value: Int?, key: KeyValueStorageKey)?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var setIntReceivedInvocations: [(siteId: String, value: Int?, key: KeyValueStorageKey)] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var setIntClosure: ((String, Int?, KeyValueStorageKey) -> Void)?

    /// Mocked function for `setInt(siteId: String, value: Int?, forKey key: KeyValueStorageKey)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func setInt(siteId: String, value: Int?, forKey key: KeyValueStorageKey) {
        mockCalled = true
        setIntCallsCount += 1
        setIntReceivedArguments = (siteId: siteId, value: value, key: key)
        setIntReceivedInvocations.append((siteId: siteId, value: value, key: key))
        setIntClosure?(siteId, value, key)
    }

    // MARK: - double

    /// Number of times the function was called.
    public private(set) var doubleCallsCount = 0
    /// `true` if the function was ever called.
    public var doubleCalled: Bool {
        doubleCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var doubleReceivedArguments: (siteId: String, key: KeyValueStorageKey)?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var doubleReceivedInvocations: [(siteId: String, key: KeyValueStorageKey)] = []
    /// Value to return from the mocked function.
    public var doubleReturnValue: Double?
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     The closure has first priority to return a value for the mocked function. If the closure returns `nil`,
     then the mock will attempt to return the value for `doubleReturnValue`
     */
    public var doubleClosure: ((String, KeyValueStorageKey) -> Double?)?

    /// Mocked function for `double(siteId: String, forKey key: KeyValueStorageKey)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func double(siteId: String, forKey key: KeyValueStorageKey) -> Double? {
        mockCalled = true
        doubleCallsCount += 1
        doubleReceivedArguments = (siteId: siteId, key: key)
        doubleReceivedInvocations.append((siteId: siteId, key: key))
        return doubleClosure.map { $0(siteId, key) } ?? doubleReturnValue
    }

    // MARK: - setDouble

    /// Number of times the function was called.
    public private(set) var setDoubleCallsCount = 0
    /// `true` if the function was ever called.
    public var setDoubleCalled: Bool {
        setDoubleCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var setDoubleReceivedArguments: (siteId: String, value: Double?, key: KeyValueStorageKey)?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var setDoubleReceivedInvocations: [(siteId: String, value: Double?, key: KeyValueStorageKey)] =
        []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var setDoubleClosure: ((String, Double?, KeyValueStorageKey) -> Void)?

    /// Mocked function for `setDouble(siteId: String, value: Double?, forKey key: KeyValueStorageKey)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func setDouble(siteId: String, value: Double?, forKey key: KeyValueStorageKey) {
        mockCalled = true
        setDoubleCallsCount += 1
        setDoubleReceivedArguments = (siteId: siteId, value: value, key: key)
        setDoubleReceivedInvocations.append((siteId: siteId, value: value, key: key))
        setDoubleClosure?(siteId, value, key)
    }

    // MARK: - string

    /// Number of times the function was called.
    public private(set) var stringCallsCount = 0
    /// `true` if the function was ever called.
    public var stringCalled: Bool {
        stringCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var stringReceivedArguments: (siteId: String, key: KeyValueStorageKey)?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var stringReceivedInvocations: [(siteId: String, key: KeyValueStorageKey)] = []
    /// Value to return from the mocked function.
    public var stringReturnValue: String?
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     The closure has first priority to return a value for the mocked function. If the closure returns `nil`,
     then the mock will attempt to return the value for `stringReturnValue`
     */
    public var stringClosure: ((String, KeyValueStorageKey) -> String?)?

    /// Mocked function for `string(siteId: String, forKey key: KeyValueStorageKey)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func string(siteId: String, forKey key: KeyValueStorageKey) -> String? {
        mockCalled = true
        stringCallsCount += 1
        stringReceivedArguments = (siteId: siteId, key: key)
        stringReceivedInvocations.append((siteId: siteId, key: key))
        return stringClosure.map { $0(siteId, key) } ?? stringReturnValue
    }

    // MARK: - setString

    /// Number of times the function was called.
    public private(set) var setStringCallsCount = 0
    /// `true` if the function was ever called.
    public var setStringCalled: Bool {
        setStringCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var setStringReceivedArguments: (siteId: String, value: String?, key: KeyValueStorageKey)?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var setStringReceivedInvocations: [(siteId: String, value: String?, key: KeyValueStorageKey)] =
        []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var setStringClosure: ((String, String?, KeyValueStorageKey) -> Void)?

    /// Mocked function for `setString(siteId: String, value: String?, forKey key: KeyValueStorageKey)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func setString(siteId: String, value: String?, forKey key: KeyValueStorageKey) {
        mockCalled = true
        setStringCallsCount += 1
        setStringReceivedArguments = (siteId: siteId, value: value, key: key)
        setStringReceivedInvocations.append((siteId: siteId, value: value, key: key))
        setStringClosure?(siteId, value, key)
    }

    // MARK: - date

    /// Number of times the function was called.
    public private(set) var dateCallsCount = 0
    /// `true` if the function was ever called.
    public var dateCalled: Bool {
        dateCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var dateReceivedArguments: (siteId: String, key: KeyValueStorageKey)?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var dateReceivedInvocations: [(siteId: String, key: KeyValueStorageKey)] = []
    /// Value to return from the mocked function.
    public var dateReturnValue: Date?
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     The closure has first priority to return a value for the mocked function. If the closure returns `nil`,
     then the mock will attempt to return the value for `dateReturnValue`
     */
    public var dateClosure: ((String, KeyValueStorageKey) -> Date?)?

    /// Mocked function for `date(siteId: String, forKey key: KeyValueStorageKey)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func date(siteId: String, forKey key: KeyValueStorageKey) -> Date? {
        mockCalled = true
        dateCallsCount += 1
        dateReceivedArguments = (siteId: siteId, key: key)
        dateReceivedInvocations.append((siteId: siteId, key: key))
        return dateClosure.map { $0(siteId, key) } ?? dateReturnValue
    }

    // MARK: - setDate

    /// Number of times the function was called.
    public private(set) var setDateCallsCount = 0
    /// `true` if the function was ever called.
    public var setDateCalled: Bool {
        setDateCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var setDateReceivedArguments: (siteId: String, value: Date?, key: KeyValueStorageKey)?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var setDateReceivedInvocations: [(siteId: String, value: Date?, key: KeyValueStorageKey)] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var setDateClosure: ((String, Date?, KeyValueStorageKey) -> Void)?

    /// Mocked function for `setDate(siteId: String, value: Date?, forKey key: KeyValueStorageKey)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func setDate(siteId: String, value: Date?, forKey key: KeyValueStorageKey) {
        mockCalled = true
        setDateCallsCount += 1
        setDateReceivedArguments = (siteId: siteId, value: value, key: key)
        setDateReceivedInvocations.append((siteId: siteId, value: value, key: key))
        setDateClosure?(siteId, value, key)
    }

    // MARK: - deleteAll

    /// Number of times the function was called.
    public private(set) var deleteAllCallsCount = 0
    /// `true` if the function was ever called.
    public var deleteAllCalled: Bool {
        deleteAllCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    public private(set) var deleteAllReceivedArguments: (String)?
    /// Arguments from *all* of the times that the function was called.
    public private(set) var deleteAllReceivedInvocations: [String] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    public var deleteAllClosure: ((String) -> Void)?

    /// Mocked function for `deleteAll(siteId: String)`. Your opportunity to return a mocked value and check result of mock in test code.
    public func deleteAll(siteId: String) {
        mockCalled = true
        deleteAllCallsCount += 1
        deleteAllReceivedArguments = siteId
        deleteAllReceivedInvocations.append(siteId)
        deleteAllClosure?(siteId)
    }
}

/**
 Class to easily create a mocked version of the `SdkCredentialsStore` class.
 This class is equipped with functions and properties ready for you to mock!

 Note: This file is automatically generated. This means the mocks should always be up-to-date and has a consistent API.
 See the SDK documentation to learn the basics behind using the mock classes in the SDK.
 */
internal class SdkCredentialsStoreMock: SdkCredentialsStore {
    /// If *any* interactions done on mock. `true` if any method or property getter/setter called.
    internal var mockCalled: Bool = false //

    internal var sharedInstanceSiteId: String?

    // MARK: - load

    /// Number of times the function was called.
    internal private(set) var loadCallsCount = 0
    /// `true` if the function was ever called.
    internal var loadCalled: Bool {
        loadCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    internal private(set) var loadReceivedArguments: (String)?
    /// Arguments from *all* of the times that the function was called.
    internal private(set) var loadReceivedInvocations: [String] = []
    /// Value to return from the mocked function.
    internal var loadReturnValue: SdkCredentials?
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     The closure has first priority to return a value for the mocked function. If the closure returns `nil`,
     then the mock will attempt to return the value for `loadReturnValue`
     */
    internal var loadClosure: ((String) -> SdkCredentials?)?

    /// Mocked function for `load(siteId: String)`. Your opportunity to return a mocked value and check result of mock in test code.
    internal func load(siteId: String) -> SdkCredentials? {
        mockCalled = true
        loadCallsCount += 1
        loadReceivedArguments = siteId
        loadReceivedInvocations.append(siteId)
        return loadClosure.map { $0(siteId) } ?? loadReturnValue
    }

    // MARK: - create

    /// Number of times the function was called.
    internal private(set) var createCallsCount = 0
    /// `true` if the function was ever called.
    internal var createCalled: Bool {
        createCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    internal private(set) var createReceivedArguments: (siteId: String, apiKey: String, region: Region)?
    /// Arguments from *all* of the times that the function was called.
    internal private(set) var createReceivedInvocations: [(siteId: String, apiKey: String, region: Region)] = []
    /// Value to return from the mocked function.
    internal var createReturnValue: SdkCredentials!
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     The closure has first priority to return a value for the mocked function. If the closure returns `nil`,
     then the mock will attempt to return the value for `createReturnValue`
     */
    internal var createClosure: ((String, String, Region) -> SdkCredentials)?

    /// Mocked function for `create(siteId: String, apiKey: String, region: Region)`. Your opportunity to return a mocked value and check result of mock in test code.
    internal func create(siteId: String, apiKey: String, region: Region) -> SdkCredentials {
        mockCalled = true
        createCallsCount += 1
        createReceivedArguments = (siteId: siteId, apiKey: apiKey, region: region)
        createReceivedInvocations.append((siteId: siteId, apiKey: apiKey, region: region))
        return createClosure.map { $0(siteId, apiKey, region) } ?? createReturnValue
    }

    // MARK: - save

    /// Number of times the function was called.
    internal private(set) var saveCallsCount = 0
    /// `true` if the function was ever called.
    internal var saveCalled: Bool {
        saveCallsCount > 0
    }

    /// The arguments from the *last* time the function was called.
    internal private(set) var saveReceivedArguments: (siteId: String, credentials: SdkCredentials)?
    /// Arguments from *all* of the times that the function was called.
    internal private(set) var saveReceivedInvocations: [(siteId: String, credentials: SdkCredentials)] = []
    /**
     Set closure to get called when function gets called. Great way to test logic or return a value for the function.
     */
    internal var saveClosure: ((String, SdkCredentials) -> Void)?

    /// Mocked function for `save(siteId: String, credentials: SdkCredentials)`. Your opportunity to return a mocked value and check result of mock in test code.
    internal func save(siteId: String, credentials: SdkCredentials) {
        mockCalled = true
        saveCallsCount += 1
        saveReceivedArguments = (siteId: siteId, credentials: credentials)
        saveReceivedInvocations.append((siteId: siteId, credentials: credentials))
        saveClosure?(siteId, credentials)
    }
}

/**
 Class to easily create a mocked version of the `TrackingInstance` class.
 This class is equipped with functions and properties ready for you to mock!

 Note: This file is automatically generated. This means the mocks should always be up-to-date and has a consistent API.
 See the SDK documentation to learn the basics behind using the mock classes in the SDK.
 */
public class TrackingInstanceMock: TrackingInstance {
    /// If *any* interactions done on mock. `true` if any method or property getter/setter called.
    public var mockCalled: Bool = false //
}
