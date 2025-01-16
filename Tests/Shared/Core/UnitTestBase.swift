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
    public let testCdpApiKey = "test"
    // Using the .shared instance of the DIGraph to ensure that all tests share the same instance and data.
    // Overriding it will work the same way as overriding the shared instance of the SDK.
    public let diGraphShared: DIGraphShared = .shared
    public var log: Logger { diGraphShared.logger }
    public var globalDataStore: GlobalDataStore { diGraphShared.globalDataStore }

    public let testSiteId = "testing"
    public var sdkConfig: SdkConfig!

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
        self.sdkConfig = sdkConfig ?? SdkConfig.Factory.create(logLevel: enableLogs ? .debug : nil)

        // setup and override dependencies before creating SDK instance, as Shared graph may be initialized and used immediately
        setUpDependencies()
        // set log level after setting up dependencies
        log.setLogLevel(self.sdkConfig.logLevel)
        // setup SDK instance and set necessary components for testing
        initializeSDKComponents()

        super.setUp()
    }

    open func setUpDependencies() {
        dateUtilStub = DateUtilStub()
        threadUtilStub = ThreadUtilStub()

        // make default behavior of tests to run async code in synchronous way to make tests more predictable.
        diGraphShared.override(value: threadUtilStub, forType: ThreadUtil.self)
    }

    @discardableResult
    open func initializeSDKComponents() -> Component? { nil }

    override open func tearDown() {
        // need to remove the observers for integration tests that utilizes actual NotificationCenter
        // otherwise, results are flaky
        diGraphShared.eventBusObserversHolder.removeAllObservers()

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
    }

    // All data that the SDK writes, delete it here so each test function has a clean environment to run and does not depend on the result of the previous test.
    open func deleteAllPersistentData() {
        deleteAllFiles()
        deleteKeyValueStoredData()
    }

    // Deletes all key/value storage pairs that the SDK could save
    private func deleteKeyValueStoredData() {
        diGraphShared.sharedKeyValueStorage.deleteAll()
    }

    private func deleteAllFiles() {
        let fileManager = FileManager.default

        let deleteFromSearchPath: (FileManager.SearchPathDirectory) -> Void = { path in
            // OK to use try! here as we want tests to crash if for some reason we are not able to delete files from the
            // device.
            // if files do not get deleted between tests, we could have false positive tests.
            // swiftlint:disable:next force_try
            let pathUrl = try! fileManager.url(for: path, in: .userDomainMask, appropriateFor: nil, create: false)
            // swiftlint:disable:next force_try
            let fileURLs = try! fileManager.contentsOfDirectory(
                at: pathUrl,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            for fileURL in fileURLs {
                try? fileManager.removeItem(at: fileURL)
            }
        }

        // Delete all files in all of the OS directories that the SDK currently saves files to.
        deleteFromSearchPath(.applicationSupportDirectory)

        // Note: We will be no longer needing this directory after merging: https://github.com/customerio/customerio-ios/pull/600
        deleteFromSearchPath(.documentDirectory)
    }

    open func waitForExpectations(file _: StaticString = #file, line _: UInt = #line) {
        waitForExpectations(0.5)
    }

    open func waitForExpectations(_ expectations: [XCTestExpectation], file _: StaticString = #file, line _: UInt = #line) async {
        await fulfillment(of: expectations, timeout: 0.5)
    }

    public func runTest(numberOfTimes: Int, test: () -> Void) {
        for _ in 0 ..< numberOfTimes {
            setUp()
            test()
            tearDown()
        }
    }

    public func runOnBackground(_ block: @escaping () -> Void) {
        Task {
            block()
        }
    }

    /*
     Run an async operation with a completion handler in a more convenient way.

     Example:
     ```
     await waitForAsyncOperation { asyncComplete in
        callCode {
            // when this code runs, callCode's completion handler was called.
            asyncComplete()
        }
     }
     ```

     This is an alternative to boilerplate `expectation()`, `expectation.fulfill()` API.
     */
    public func waitForAsyncOperation(_ block: @escaping (@escaping () -> Void) -> Void) async {
        await withCheckedContinuation { continuation in
            block {
                continuation.resume()
            }
        }
    }

    // You can store static files in Tests/Shared/SampleDataFiles and read those files with this function.
    public func readSampleDataFile(subdirectory: String, fileName: String) -> String {
        SampleDataFilesUtil(fileStore: diGraphShared.fileStorage).readFileContents(fileName: fileName, subdirectory: subdirectory)
    }
}
