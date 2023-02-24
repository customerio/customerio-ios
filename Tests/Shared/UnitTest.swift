@testable import CioTracking
@testable import Common
import Foundation
import XCTest

/**
 Handy base class for tests in this test suite. Extend this class to have access to some handy properties and functions you
 may want to use in your tests.

 We use a base class instead of simply a utility class because we can't access `setup` and `teardown` functions with a util class.
 */
open class UnitTest: XCTestCase {
    /*
     Handy objects tests might need to use
     */
    // Prefer to use real instance of key value storage because (1) mocking it is annoying and (2) tests react closely
    // to real app.
    public let testSiteId = "testing"
    public var diGraph: DIGraph!

    public var sdkConfig: SdkConfig {
        diGraph!.sdkConfig
    }

    public var keyValueStorage: KeyValueStorage {
        diGraph.keyValueStorage
    }

    public var profileStore: ProfileStore {
        diGraph.profileStore
    }

    public var log: Logger {
        diGraph.logger
    }

    public var jsonAdapter: JsonAdapter {
        JsonAdapter(log: log)
    }

    public var retryPolicyMock: HttpRetryPolicyMock!

    public var dateUtilStub: DateUtilStub!

    public var threadUtilStub: ThreadUtilStub!
    private var runTestFunctionSyncronously: Bool! // gets populated in setUp() so we can use in tearDown()

    public var lockManager: LockManager {
        LockManager()
    }

    // Must override XCTest super class in order for us to customize the test suite.
    // This method is not meant to be overriden in our own subclasses. Instead, override the other setUp(...) function instead to customize behavior.
    override open func setUp() {
        setUp(enableLogs: false) // call other setUp function to run the logic in this subclass.
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
     @param runCodeSyncronously Overrides threading behavior in SDK code to run all asynchronous code in a syncronous way.
     @param modifySdkConfig Allows you to change configuration options before the SDKConfig instnace is created for you.
     */
    public func setUp(enableLogs: Bool = false, runCodeSyncronously: Bool = true, modifySdkConfig: ((inout SdkConfig) -> Void)? = nil) {
        super.setUp()

        var newSdkConfig = SdkConfig.Factory.create(region: Region.US)
        if enableLogs {
            newSdkConfig.logLevel = CioLogLevel.debug
        }

        modifySdkConfig?(&newSdkConfig)

        diGraph = DIGraph(siteId: testSiteId, apiKey: "", sdkConfig: newSdkConfig)

        dateUtilStub = DateUtilStub()

        threadUtilStub = ThreadUtilStub()
        runTestFunctionSyncronously = runCodeSyncronously
        if runCodeSyncronously {
            // Override thread util to make async code run syncronously. This can make unit tests more predictable and easier to write.
            // However, not all test functions should run syncronously. You decide what's best based on what your test function is verifying.
            diGraph.override(value: threadUtilStub, forType: ThreadUtil.self)
        }

        // Set the default sleep time for retry policy to a small amount to make tests run fast while also testing the
        // HTTP retry policy's real code.
        retryPolicyMock = HttpRetryPolicyMock()
        retryPolicyMock.underlyingNextSleepTime = 0.01

        deleteAllPersistantData()

        super.setUp()
    }

    override open func tearDown() {
        // It's very important that the SDK code executes on the thread we expected it to in a test function. This asserts that our test suite was setup correctly to run test function on the intended thread.
        if !runTestFunctionSyncronously {
            XCTAssertFalse(threadUtilStub.mockCalled)
        }

        Mocks.shared.resetAll()

        deleteAllPersistantData()

        diGraph.reset()

        super.tearDown()
    }

    public func deleteAllPersistantData() {
        deleteKeyValueStorage()
        CustomerIO.resetSharedInstance()
        deleteAllFiles()
    }

    // function meant to only be in tests as deleting all files from a search path (where app files can be stored!) is
    // not a good idea.
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

        deleteFromSearchPath(.applicationSupportDirectory)
    }

    /**
     Although key value storage is separated by siteId, we want to delete
     common siteId's that we know about.
     */
    func deleteKeyValueStorage() {
        // The SDK does not use `UserDefaults.standard`, but in case a test needs to,
        // let's delete the data for each test.
        UserDefaults.standard.deleteAll()

        // delete key value data that belongs to the site-id.
        keyValueStorage.deleteAll()

        // delete key value data that is global to all site-ids in the SDK.
        diGraph.globalDataStore.deleteAll()
    }

    open func waitForExpectations(file _: StaticString = #file, line _: UInt = #line) {
        waitForExpectations(0.5)
    }
}

public extension UnitTest {
    func waitForQueueToFinishRunningTasks(
        _ queue: Queue,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let queueExpectation = expectation(description: "Expect queue to run all tasks.")
        queue.run {
            queueExpectation.fulfill()
        }

        waitForExpectations(for: [queueExpectation], file: file, line: line)
    }
}
