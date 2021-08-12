// Generated using Sourcery 1.5.0 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT
import Foundation

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

class KeyValueStorageMock: KeyValueStorage {
    var mockCalled: Bool = false // if *any* interactions done on mock. Sets/gets or methods called.

    // MARK: - integer

    var integerForKeyCallsCount = 0
    var integerForKeyCalled: Bool {
        integerForKeyCallsCount > 0
    }

    var integerForKeyReceivedKey: KeyValueStorageKey?
    var integerForKeyReceivedInvocations: [KeyValueStorageKey] = []
    var integerForKeyReturnValue: Int?
    var integerForKeyClosure: ((KeyValueStorageKey) -> Int?)?

    func integer(forKey key: KeyValueStorageKey) -> Int? {
        mockCalled = true
        integerForKeyCallsCount += 1
        integerForKeyReceivedKey = key
        integerForKeyReceivedInvocations.append(key)
        return integerForKeyClosure.map { $0(key) } ?? integerForKeyReturnValue
    }

    // MARK: - setInt

    var setIntForKeyCallsCount = 0
    var setIntForKeyCalled: Bool {
        setIntForKeyCallsCount > 0
    }

    var setIntForKeyReceivedArguments: (value: Int?, key: KeyValueStorageKey)?
    var setIntForKeyReceivedInvocations: [(value: Int?, key: KeyValueStorageKey)] = []
    var setIntForKeyClosure: ((Int?, KeyValueStorageKey) -> Void)?

    func setInt(_ value: Int?, forKey key: KeyValueStorageKey) {
        mockCalled = true
        setIntForKeyCallsCount += 1
        setIntForKeyReceivedArguments = (value: value, key: key)
        setIntForKeyReceivedInvocations.append((value: value, key: key))
        setIntForKeyClosure?(value, key)
    }

    // MARK: - double

    var doubleForKeyCallsCount = 0
    var doubleForKeyCalled: Bool {
        doubleForKeyCallsCount > 0
    }

    var doubleForKeyReceivedKey: KeyValueStorageKey?
    var doubleForKeyReceivedInvocations: [KeyValueStorageKey] = []
    var doubleForKeyReturnValue: Double?
    var doubleForKeyClosure: ((KeyValueStorageKey) -> Double?)?

    func double(forKey key: KeyValueStorageKey) -> Double? {
        mockCalled = true
        doubleForKeyCallsCount += 1
        doubleForKeyReceivedKey = key
        doubleForKeyReceivedInvocations.append(key)
        return doubleForKeyClosure.map { $0(key) } ?? doubleForKeyReturnValue
    }

    // MARK: - setDouble

    var setDoubleForKeyCallsCount = 0
    var setDoubleForKeyCalled: Bool {
        setDoubleForKeyCallsCount > 0
    }

    var setDoubleForKeyReceivedArguments: (value: Double?, key: KeyValueStorageKey)?
    var setDoubleForKeyReceivedInvocations: [(value: Double?, key: KeyValueStorageKey)] = []
    var setDoubleForKeyClosure: ((Double?, KeyValueStorageKey) -> Void)?

    func setDouble(_ value: Double?, forKey key: KeyValueStorageKey) {
        mockCalled = true
        setDoubleForKeyCallsCount += 1
        setDoubleForKeyReceivedArguments = (value: value, key: key)
        setDoubleForKeyReceivedInvocations.append((value: value, key: key))
        setDoubleForKeyClosure?(value, key)
    }

    // MARK: - string

    var stringForKeyCallsCount = 0
    var stringForKeyCalled: Bool {
        stringForKeyCallsCount > 0
    }

    var stringForKeyReceivedKey: KeyValueStorageKey?
    var stringForKeyReceivedInvocations: [KeyValueStorageKey] = []
    var stringForKeyReturnValue: String?
    var stringForKeyClosure: ((KeyValueStorageKey) -> String?)?

    func string(forKey key: KeyValueStorageKey) -> String? {
        mockCalled = true
        stringForKeyCallsCount += 1
        stringForKeyReceivedKey = key
        stringForKeyReceivedInvocations.append(key)
        return stringForKeyClosure.map { $0(key) } ?? stringForKeyReturnValue
    }

    // MARK: - setString

    var setStringForKeyCallsCount = 0
    var setStringForKeyCalled: Bool {
        setStringForKeyCallsCount > 0
    }

    var setStringForKeyReceivedArguments: (value: String?, key: KeyValueStorageKey)?
    var setStringForKeyReceivedInvocations: [(value: String?, key: KeyValueStorageKey)] = []
    var setStringForKeyClosure: ((String?, KeyValueStorageKey) -> Void)?

    func setString(_ value: String?, forKey key: KeyValueStorageKey) {
        mockCalled = true
        setStringForKeyCallsCount += 1
        setStringForKeyReceivedArguments = (value: value, key: key)
        setStringForKeyReceivedInvocations.append((value: value, key: key))
        setStringForKeyClosure?(value, key)
    }

    // MARK: - date

    var dateForKeyCallsCount = 0
    var dateForKeyCalled: Bool {
        dateForKeyCallsCount > 0
    }

    var dateForKeyReceivedKey: KeyValueStorageKey?
    var dateForKeyReceivedInvocations: [KeyValueStorageKey] = []
    var dateForKeyReturnValue: Date?
    var dateForKeyClosure: ((KeyValueStorageKey) -> Date?)?

    func date(forKey key: KeyValueStorageKey) -> Date? {
        mockCalled = true
        dateForKeyCallsCount += 1
        dateForKeyReceivedKey = key
        dateForKeyReceivedInvocations.append(key)
        return dateForKeyClosure.map { $0(key) } ?? dateForKeyReturnValue
    }

    // MARK: - setDate

    var setDateForKeyCallsCount = 0
    var setDateForKeyCalled: Bool {
        setDateForKeyCallsCount > 0
    }

    var setDateForKeyReceivedArguments: (value: Date?, key: KeyValueStorageKey)?
    var setDateForKeyReceivedInvocations: [(value: Date?, key: KeyValueStorageKey)] = []
    var setDateForKeyClosure: ((Date?, KeyValueStorageKey) -> Void)?

    func setDate(_ value: Date?, forKey key: KeyValueStorageKey) {
        mockCalled = true
        setDateForKeyCallsCount += 1
        setDateForKeyReceivedArguments = (value: value, key: key)
        setDateForKeyReceivedInvocations.append((value: value, key: key))
        setDateForKeyClosure?(value, key)
    }

    // MARK: - deleteAll

    var deleteAllCallsCount = 0
    var deleteAllCalled: Bool {
        deleteAllCallsCount > 0
    }

    var deleteAllClosure: (() -> Void)?

    func deleteAll() {
        mockCalled = true
        deleteAllCallsCount += 1
        deleteAllClosure?()
    }
}

class SdkConfigManagerMock: SdkConfigManager {
    var mockCalled: Bool = false // if *any* interactions done on mock. Sets/gets or methods called.

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
