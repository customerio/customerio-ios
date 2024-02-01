@testable import CioInternalCommon
import Foundation
import XCTest

/// Serves as the base class for all tests within the SDK, offering common setup, teardown, and
/// utility methods shared across test cases. This class simplifies the initialization of the SDK/modules,
/// mock objects, test data, and other shared resources, ensuring a consistent testing environment and
/// minimizing boilerplate in individual test cases.
///
/// The generic `Component` parameter represents the module interface, providing convenient and direct access
/// to the module's public APIs being tested. `Component` can be specified as the SDK (e.g., `CustomerIO`)
/// or a specific module (e.g., `MessagingPush`).
///
/// For SDK-wide tests, child classes can conveniently inherit from `UnitTest`, designed specifically for testing only SDK APIs.
open class UnitTestBase<Component>: XCTestCase {
    public let testWriteKey = "test"
    public var diGraphShared: DIGraphShared!
    public var log: Logger { diGraphShared.logger }
    public var globalDataStore: GlobalDataStore { diGraphShared.globalDataStore }

    public let testSiteId = "testing"
    public var diGraph: DIGraph!
    public var sdkConfig: SdkConfig { diGraph.sdkConfig }

    public var jsonAdapter: JsonAdapter { JsonAdapter(log: log) }
    public var lockManager: LockManager { LockManager() }
    public var dateUtilStub: DateUtilStub!
    public var threadUtilStub: ThreadUtilStub!

    override open func setUp() {
        setUp(enableLogs: false, modifySdkConfig: nil)
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
    open func setUp(
        enableLogs: Bool = false,
        siteId: String? = nil,
        modifySdkConfig: ((inout SdkConfig) -> Void)?
    ) {
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

        super.setUp()
    }

    open func setUpDependencies() {
        dateUtilStub = DateUtilStub()
        threadUtilStub = ThreadUtilStub()

        // make default behavior of tests to run async code in synchronous way to make tests more predictable.
        diGraphShared.override(value: threadUtilStub, forType: ThreadUtil.self)
        diGraph.override(value: threadUtilStub, forType: ThreadUtil.self)
    }

    @discardableResult
    open func initializeSDKComponents() -> Component? { nil }

    override open func tearDown() {
        cleanupTestEnvironment()
        super.tearDown()
    }

    // Clean up the test environment by releasing resources, clearing mocks, and resetting states during teardown.
    open func cleanupTestEnvironment() {
        Mocks.shared.resetAll()
        // Delete all persistent data to ensure a clean state for each test when called during teardown.
        deleteAllPersistantData()

        diGraphShared.reset()
        diGraph.reset()
    }

    open func deleteAllPersistantData() {
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

    open func waitForExpectations(file _: StaticString = #file, line _: UInt = #line) {
        waitForExpectations(0.5)
    }
}
