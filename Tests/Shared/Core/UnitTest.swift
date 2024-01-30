@testable import CioInternalCommon
@testable import CioTracking
import Foundation
import XCTest

/**
 Handy base class for tests in this test suite. Extend this class to have access to some handy properties and functions you
 may want to use in your tests.

 We use a base class instead of simply a utility class because we can't access `setup` and `teardown` functions with a util class.
 */
open class UnitTest: XCTestCase {
    public let testSiteId = "testing"
    public let testWriteKey = "test"

    public var diGraphShared: DIGraphShared!
    public var diGraph: DIGraph!

    open var log: Logger {
        diGraphShared.logger
    }

    open var globalDataStore: GlobalDataStore {
        diGraphShared.globalDataStore
    }

    public var sdkConfig: SdkConfig {
        diGraph.sdkConfig
    }

    public var jsonAdapter: JsonAdapter {
        JsonAdapter(log: log)
    }

    public var dateUtilStub: DateUtilStub!

    public var threadUtilStub: ThreadUtilStub!

    public var lockManager: LockManager {
        LockManager()
    }

    /**
     Perform setup before each test function runs in your test class.
     Example:
     ```
     override func setUp() {
       super.setUp() // <-- this line calls this function in UnitTest file.

       // do some setup logic, here.
     }
     ```

     @param enableLogs Enables logging for the test class. Can be useful for debugging. Disabled by default it's too noisey and unhelpful when logs are enabled for all tests.
     @param modifySdkConfig Allows you to change configuration options before the SDKConfig instnace is created for you.
     */
    override open func setUp() {
        setUp(enableLogs: false, modifySdkConfig: nil)
    }

    open func setUp(
        enableLogs: Bool = false,
        siteId: String? = nil,
        modifySdkConfig: ((inout SdkConfig) -> Void)?
    ) {
        super.setUp()

        var newSdkConfig = SdkConfig.Factory.create(siteId: siteId ?? testSiteId, apiKey: "", region: Region.US)
        if enableLogs {
            newSdkConfig.logLevel = CioLogLevel.debug
        }
        modifySdkConfig?(&newSdkConfig)

        diGraphShared = DIGraphShared()
        diGraph = DIGraph(sdkConfig: newSdkConfig)

        // setup and override dependencies before creating SDK instance, as Shared graph may be initialized and used immediately
        setUpDependencies()
        // setup SDK instance and set necessary components for testing
        initializeSDKComponents()
    }

    open func setUpDependencies() {
        dateUtilStub = DateUtilStub()
        threadUtilStub = ThreadUtilStub()

        // make default behavior of tests to run async code in synchronous way to make tests more predictable.
        diGraphShared.override(value: threadUtilStub, forType: ThreadUtil.self)
        diGraph.override(value: threadUtilStub, forType: ThreadUtil.self)
    }

    @discardableResult
    open func initializeSDKComponents() -> CustomerIO? {
        CustomerIO.shared
    }

    override open func tearDown() {
        Mocks.shared.resetAll()

        deleteAllPersistantData()

        diGraphShared.reset()
        diGraph.reset()

        resetTestInstances()

        super.tearDown()
    }

    open func deleteAllPersistantData() {
        deleteKeyValueStorage()
        deleteAllFiles()
    }

    /// delete
    open func deleteKeyValueStorage() {
        // The SDK does not use `UserDefaults.standard`, but in case a test needs to,
        // let's delete the data for each test.
        UserDefaults.standard.deleteAll()

        // delete key value data that belongs to shared storage.
        diGraphShared.sharedKeyValueStorage.deleteAll()
        // delete key value data that belongs to the site-id.
        // although key value storage is separated by siteId, we want to delete common siteId's that we know about.
        diGraph.keyValueStorage.deleteAll()

        // delete key value data that is global to all api keys in the SDK.
        globalDataStore.deleteAll()
    }

    /// delete
    open func deleteAllFiles() {}

    /// reset
    open func resetTestInstances() {
        CustomerIO.resetSharedInstance()
    }

    open func waitForExpectations(file _: StaticString = #file, line _: UInt = #line) {
        waitForExpectations(0.5)
    }
}
