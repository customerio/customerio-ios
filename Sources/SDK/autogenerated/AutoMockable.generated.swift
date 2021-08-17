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

class HttpClientMock: HttpClient {
    var mockCalled: Bool = false // if *any* interactions done on mock. Sets/gets or methods called.

    // MARK: - request

    var requestHeadersBodyOnCompleteCallsCount = 0
    var requestHeadersBodyOnCompleteCalled: Bool {
        requestHeadersBodyOnCompleteCallsCount > 0
    }

    var requestHeadersBodyOnCompleteReceivedArguments: (endpoint: HttpEndpoint, headers: HttpHeaders?, body: Data?,
                                                        onComplete: (Result<Data, HttpRequestError>) -> Void)?
    var requestHeadersBodyOnCompleteReceivedInvocations: [(endpoint: HttpEndpoint, headers: HttpHeaders?, body: Data?,
                                                           onComplete: (Result<Data, HttpRequestError>) -> Void)] = []
    var requestHeadersBodyOnCompleteClosure: ((HttpEndpoint, HttpHeaders?, Data?,
                                               @escaping (Result<Data, HttpRequestError>) -> Void) -> Void)?

    func request(
        _ endpoint: HttpEndpoint,
        headers: HttpHeaders?,
        body: Data?,
        onComplete: @escaping (Result<Data, HttpRequestError>) -> Void
    ) {
        mockCalled = true
        requestHeadersBodyOnCompleteCallsCount += 1
        requestHeadersBodyOnCompleteReceivedArguments = (endpoint: endpoint, headers: headers, body: body,
                                                         onComplete: onComplete)
        requestHeadersBodyOnCompleteReceivedInvocations
            .append((endpoint: endpoint, headers: headers, body: body, onComplete: onComplete))
        requestHeadersBodyOnCompleteClosure?(endpoint, headers, body, onComplete)
    }
}

class HttpRequestRunnerMock: HttpRequestRunner {
    var mockCalled: Bool = false // if *any* interactions done on mock. Sets/gets or methods called.

    // MARK: - getUrl

    var getUrlEndpointRegionCallsCount = 0
    var getUrlEndpointRegionCalled: Bool {
        getUrlEndpointRegionCallsCount > 0
    }

    var getUrlEndpointRegionReceivedArguments: (endpoint: HttpEndpoint, region: Region)?
    var getUrlEndpointRegionReceivedInvocations: [(endpoint: HttpEndpoint, region: Region)] = []
    var getUrlEndpointRegionReturnValue: URL?
    var getUrlEndpointRegionClosure: ((HttpEndpoint, Region) -> URL?)?

    func getUrl(endpoint: HttpEndpoint, region: Region) -> URL? {
        mockCalled = true
        getUrlEndpointRegionCallsCount += 1
        getUrlEndpointRegionReceivedArguments = (endpoint: endpoint, region: region)
        getUrlEndpointRegionReceivedInvocations.append((endpoint: endpoint, region: region))
        return getUrlEndpointRegionClosure.map { $0(endpoint, region) } ?? getUrlEndpointRegionReturnValue
    }

    // MARK: - request

    var requestCallsCount = 0
    var requestCalled: Bool {
        requestCallsCount > 0
    }

    var requestReceivedArguments: (params: RequestParams, onComplete: (Data?, HTTPURLResponse?, Error?) -> Void)?
    var requestReceivedInvocations: [(params: RequestParams, onComplete: (Data?, HTTPURLResponse?, Error?) -> Void)] =
        []
    var requestClosure: ((RequestParams, @escaping (Data?, HTTPURLResponse?, Error?) -> Void) -> Void)?

    func request(_ params: RequestParams, _ onComplete: @escaping (Data?, HTTPURLResponse?, Error?) -> Void) {
        mockCalled = true
        requestCallsCount += 1
        requestReceivedArguments = (params: params, onComplete: onComplete)
        requestReceivedInvocations.append((params: params, onComplete: onComplete))
        requestClosure?(params, onComplete)
    }
}

class KeyValueStorageMock: KeyValueStorage {
    var mockCalled: Bool = false // if *any* interactions done on mock. Sets/gets or methods called.

    var underlyingSharedSiteId: String!
    var sharedSiteIdCalled = false
    var sharedSiteIdGetCalled = false
    var sharedSiteIdSetCalled = false
    var sharedSiteId: String {
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

    var integerSiteIdForKeyCallsCount = 0
    var integerSiteIdForKeyCalled: Bool {
        integerSiteIdForKeyCallsCount > 0
    }

    var integerSiteIdForKeyReceivedArguments: (siteId: String, key: KeyValueStorageKey)?
    var integerSiteIdForKeyReceivedInvocations: [(siteId: String, key: KeyValueStorageKey)] = []
    var integerSiteIdForKeyReturnValue: Int?
    var integerSiteIdForKeyClosure: ((String, KeyValueStorageKey) -> Int?)?

    func integer(siteId: String, forKey key: KeyValueStorageKey) -> Int? {
        mockCalled = true
        integerSiteIdForKeyCallsCount += 1
        integerSiteIdForKeyReceivedArguments = (siteId: siteId, key: key)
        integerSiteIdForKeyReceivedInvocations.append((siteId: siteId, key: key))
        return integerSiteIdForKeyClosure.map { $0(siteId, key) } ?? integerSiteIdForKeyReturnValue
    }

    // MARK: - setInt

    var setIntSiteIdValueForKeyCallsCount = 0
    var setIntSiteIdValueForKeyCalled: Bool {
        setIntSiteIdValueForKeyCallsCount > 0
    }

    var setIntSiteIdValueForKeyReceivedArguments: (siteId: String, value: Int?, key: KeyValueStorageKey)?
    var setIntSiteIdValueForKeyReceivedInvocations: [(siteId: String, value: Int?, key: KeyValueStorageKey)] = []
    var setIntSiteIdValueForKeyClosure: ((String, Int?, KeyValueStorageKey) -> Void)?

    func setInt(siteId: String, value: Int?, forKey key: KeyValueStorageKey) {
        mockCalled = true
        setIntSiteIdValueForKeyCallsCount += 1
        setIntSiteIdValueForKeyReceivedArguments = (siteId: siteId, value: value, key: key)
        setIntSiteIdValueForKeyReceivedInvocations.append((siteId: siteId, value: value, key: key))
        setIntSiteIdValueForKeyClosure?(siteId, value, key)
    }

    // MARK: - double

    var doubleSiteIdForKeyCallsCount = 0
    var doubleSiteIdForKeyCalled: Bool {
        doubleSiteIdForKeyCallsCount > 0
    }

    var doubleSiteIdForKeyReceivedArguments: (siteId: String, key: KeyValueStorageKey)?
    var doubleSiteIdForKeyReceivedInvocations: [(siteId: String, key: KeyValueStorageKey)] = []
    var doubleSiteIdForKeyReturnValue: Double?
    var doubleSiteIdForKeyClosure: ((String, KeyValueStorageKey) -> Double?)?

    func double(siteId: String, forKey key: KeyValueStorageKey) -> Double? {
        mockCalled = true
        doubleSiteIdForKeyCallsCount += 1
        doubleSiteIdForKeyReceivedArguments = (siteId: siteId, key: key)
        doubleSiteIdForKeyReceivedInvocations.append((siteId: siteId, key: key))
        return doubleSiteIdForKeyClosure.map { $0(siteId, key) } ?? doubleSiteIdForKeyReturnValue
    }

    // MARK: - setDouble

    var setDoubleSiteIdValueForKeyCallsCount = 0
    var setDoubleSiteIdValueForKeyCalled: Bool {
        setDoubleSiteIdValueForKeyCallsCount > 0
    }

    var setDoubleSiteIdValueForKeyReceivedArguments: (siteId: String, value: Double?, key: KeyValueStorageKey)?
    var setDoubleSiteIdValueForKeyReceivedInvocations: [(siteId: String, value: Double?, key: KeyValueStorageKey)] = []
    var setDoubleSiteIdValueForKeyClosure: ((String, Double?, KeyValueStorageKey) -> Void)?

    func setDouble(siteId: String, value: Double?, forKey key: KeyValueStorageKey) {
        mockCalled = true
        setDoubleSiteIdValueForKeyCallsCount += 1
        setDoubleSiteIdValueForKeyReceivedArguments = (siteId: siteId, value: value, key: key)
        setDoubleSiteIdValueForKeyReceivedInvocations.append((siteId: siteId, value: value, key: key))
        setDoubleSiteIdValueForKeyClosure?(siteId, value, key)
    }

    // MARK: - string

    var stringSiteIdForKeyCallsCount = 0
    var stringSiteIdForKeyCalled: Bool {
        stringSiteIdForKeyCallsCount > 0
    }

    var stringSiteIdForKeyReceivedArguments: (siteId: String, key: KeyValueStorageKey)?
    var stringSiteIdForKeyReceivedInvocations: [(siteId: String, key: KeyValueStorageKey)] = []
    var stringSiteIdForKeyReturnValue: String?
    var stringSiteIdForKeyClosure: ((String, KeyValueStorageKey) -> String?)?

    func string(siteId: String, forKey key: KeyValueStorageKey) -> String? {
        mockCalled = true
        stringSiteIdForKeyCallsCount += 1
        stringSiteIdForKeyReceivedArguments = (siteId: siteId, key: key)
        stringSiteIdForKeyReceivedInvocations.append((siteId: siteId, key: key))
        return stringSiteIdForKeyClosure.map { $0(siteId, key) } ?? stringSiteIdForKeyReturnValue
    }

    // MARK: - setString

    var setStringSiteIdValueForKeyCallsCount = 0
    var setStringSiteIdValueForKeyCalled: Bool {
        setStringSiteIdValueForKeyCallsCount > 0
    }

    var setStringSiteIdValueForKeyReceivedArguments: (siteId: String, value: String?, key: KeyValueStorageKey)?
    var setStringSiteIdValueForKeyReceivedInvocations: [(siteId: String, value: String?, key: KeyValueStorageKey)] = []
    var setStringSiteIdValueForKeyClosure: ((String, String?, KeyValueStorageKey) -> Void)?

    func setString(siteId: String, value: String?, forKey key: KeyValueStorageKey) {
        mockCalled = true
        setStringSiteIdValueForKeyCallsCount += 1
        setStringSiteIdValueForKeyReceivedArguments = (siteId: siteId, value: value, key: key)
        setStringSiteIdValueForKeyReceivedInvocations.append((siteId: siteId, value: value, key: key))
        setStringSiteIdValueForKeyClosure?(siteId, value, key)
    }

    // MARK: - date

    var dateSiteIdForKeyCallsCount = 0
    var dateSiteIdForKeyCalled: Bool {
        dateSiteIdForKeyCallsCount > 0
    }

    var dateSiteIdForKeyReceivedArguments: (siteId: String, key: KeyValueStorageKey)?
    var dateSiteIdForKeyReceivedInvocations: [(siteId: String, key: KeyValueStorageKey)] = []
    var dateSiteIdForKeyReturnValue: Date?
    var dateSiteIdForKeyClosure: ((String, KeyValueStorageKey) -> Date?)?

    func date(siteId: String, forKey key: KeyValueStorageKey) -> Date? {
        mockCalled = true
        dateSiteIdForKeyCallsCount += 1
        dateSiteIdForKeyReceivedArguments = (siteId: siteId, key: key)
        dateSiteIdForKeyReceivedInvocations.append((siteId: siteId, key: key))
        return dateSiteIdForKeyClosure.map { $0(siteId, key) } ?? dateSiteIdForKeyReturnValue
    }

    // MARK: - setDate

    var setDateSiteIdValueForKeyCallsCount = 0
    var setDateSiteIdValueForKeyCalled: Bool {
        setDateSiteIdValueForKeyCallsCount > 0
    }

    var setDateSiteIdValueForKeyReceivedArguments: (siteId: String, value: Date?, key: KeyValueStorageKey)?
    var setDateSiteIdValueForKeyReceivedInvocations: [(siteId: String, value: Date?, key: KeyValueStorageKey)] = []
    var setDateSiteIdValueForKeyClosure: ((String, Date?, KeyValueStorageKey) -> Void)?

    func setDate(siteId: String, value: Date?, forKey key: KeyValueStorageKey) {
        mockCalled = true
        setDateSiteIdValueForKeyCallsCount += 1
        setDateSiteIdValueForKeyReceivedArguments = (siteId: siteId, value: value, key: key)
        setDateSiteIdValueForKeyReceivedInvocations.append((siteId: siteId, value: value, key: key))
        setDateSiteIdValueForKeyClosure?(siteId, value, key)
    }

    // MARK: - deleteAll

    var deleteAllSiteIdCallsCount = 0
    var deleteAllSiteIdCalled: Bool {
        deleteAllSiteIdCallsCount > 0
    }

    var deleteAllSiteIdReceivedSiteId: String?
    var deleteAllSiteIdReceivedInvocations: [String] = []
    var deleteAllSiteIdClosure: ((String) -> Void)?

    func deleteAll(siteId: String) {
        mockCalled = true
        deleteAllSiteIdCallsCount += 1
        deleteAllSiteIdReceivedSiteId = siteId
        deleteAllSiteIdReceivedInvocations.append(siteId)
        deleteAllSiteIdClosure?(siteId)
    }
}

class SdkConfigStoreMock: SdkConfigStore {
    var mockCalled: Bool = false // if *any* interactions done on mock. Sets/gets or methods called.

    var sharedInstanceSiteId: String?

    // MARK: - load

    var loadSiteIdCallsCount = 0
    var loadSiteIdCalled: Bool {
        loadSiteIdCallsCount > 0
    }

    var loadSiteIdReceivedSiteId: String?
    var loadSiteIdReceivedInvocations: [String] = []
    var loadSiteIdReturnValue: SdkConfig?
    var loadSiteIdClosure: ((String) -> SdkConfig?)?

    func load(siteId: String) -> SdkConfig? {
        mockCalled = true
        loadSiteIdCallsCount += 1
        loadSiteIdReceivedSiteId = siteId
        loadSiteIdReceivedInvocations.append(siteId)
        return loadSiteIdClosure.map { $0(siteId) } ?? loadSiteIdReturnValue
    }

    // MARK: - create

    var createSiteIdApiKeyRegionCallsCount = 0
    var createSiteIdApiKeyRegionCalled: Bool {
        createSiteIdApiKeyRegionCallsCount > 0
    }

    var createSiteIdApiKeyRegionReceivedArguments: (siteId: String, apiKey: String, region: Region)?
    var createSiteIdApiKeyRegionReceivedInvocations: [(siteId: String, apiKey: String, region: Region)] = []
    var createSiteIdApiKeyRegionReturnValue: SdkConfig!
    var createSiteIdApiKeyRegionClosure: ((String, String, Region) -> SdkConfig)?

    func create(siteId: String, apiKey: String, region: Region) -> SdkConfig {
        mockCalled = true
        createSiteIdApiKeyRegionCallsCount += 1
        createSiteIdApiKeyRegionReceivedArguments = (siteId: siteId, apiKey: apiKey, region: region)
        createSiteIdApiKeyRegionReceivedInvocations.append((siteId: siteId, apiKey: apiKey, region: region))
        return createSiteIdApiKeyRegionClosure.map { $0(siteId, apiKey, region) } ?? createSiteIdApiKeyRegionReturnValue
    }

    // MARK: - save

    var saveSiteIdConfigCallsCount = 0
    var saveSiteIdConfigCalled: Bool {
        saveSiteIdConfigCallsCount > 0
    }

    var saveSiteIdConfigReceivedArguments: (siteId: String, config: SdkConfig)?
    var saveSiteIdConfigReceivedInvocations: [(siteId: String, config: SdkConfig)] = []
    var saveSiteIdConfigClosure: ((String, SdkConfig) -> Void)?

    func save(siteId: String, config: SdkConfig) {
        mockCalled = true
        saveSiteIdConfigCallsCount += 1
        saveSiteIdConfigReceivedArguments = (siteId: siteId, config: config)
        saveSiteIdConfigReceivedInvocations.append((siteId: siteId, config: config))
        saveSiteIdConfigClosure?(siteId, config)
    }
}
