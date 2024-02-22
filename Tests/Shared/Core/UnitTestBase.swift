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
    // Using the .shared instance of the DIGraph to ensure that all tests share the same instance and data.
    // Overriding it will work the same way as overriding the shared instance of the SDK.
    public let diGraphShared: DIGraphShared = .shared
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
        setUp(sdkConfig: nil)
    }

    /**
     Performs initial setup before the execution of each test method in the test class.

     This method should be overridden to include any setup logic required before each test.
     Call the base implementation in `UnitTestBase` with `super.setUp()` to ensure proper setup, as shown below:

     ```
     override func setUp() {
       super.setUp()    // <-- calls the base class setup

       // insert setup logic here.
     }
     ```

     To skip the default setup in order to modify SDK/module settings directly within the test function,
     `setUp` can be overridden as empty, without calling `super.setUp()`, like this:

     ```
     override func setUp() {
         // intentionally empty to skip default setup
     }
     ```

     Then, customize the SDK/module configuration in test function as follows:

     ```
     override func setUp() {
         super.setUp(modifySdkConfig: { config in    // <-- calls the base class setup and modifies config
             config.autoTrackDeviceAttributes = false
         })

         // additional setup logic here.
     }
     ```

     @param enableLogs Enables logging for the test class. Can be useful for debugging. Disabled by default as it's too noisey and unhelpful when logs are enabled for all tests.
     @param modifySdkConfig Closure allowing customization of the SDK/Module configuration before the SDK/Module instance is initialized.
     */
    open func setUp(enableLogs: Bool = false, sdkConfig: SdkConfig? = nil) {
        var newSdkConfig = sdkConfig ?? SdkConfig.Factory.create(siteId: testSiteId, apiKey: "", region: Region.US)
        if enableLogs {
            newSdkConfig.logLevel = CioLogLevel.debug
        }

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
        // Delete all persistent data to ensure a clean state for each test when called during teardown.
        deleteAllPersistentData()
        // Reset mocks at the very end to prevent `EXC_BAD_ACCESS` errors by avoiding access to deallocated objects.
        Mocks.shared.resetAll()

        // reset DI graphs to their initial state.
        diGraphShared.reset()
        diGraph.reset()
    }

    open func deleteAllPersistentData() {
        var expectations: [XCTestExpectation] = []

        let resetEventBusExpectation = XCTestExpectation(description: "reset EventBus to initial state")
        expectations.append(resetEventBusExpectation)
        Task {
            await diGraphShared.eventBusHandler.reset()
            resetEventBusExpectation.fulfill()
        }

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

        // cleaning up data should already have completed by now.
        // but we'll wait for a bit to ensure it's done and not cause any issues for the next test.
        wait(for: expectations, timeout: 5.0)
    }

    open func waitForExpectations(file _: StaticString = #file, line _: UInt = #line) {
        waitForExpectations(0.5)
    }

    public func runTest(numberOfTimes: Int, test: () -> Void) {
        for _ in 0 ..< numberOfTimes {
            setUp()
            test()
            tearDown()
        }
    }

    public func runOnBackground(_ block: @escaping () -> Void) {
        CioThreadUtil().runBackground {
            block()
        }
    }
}
