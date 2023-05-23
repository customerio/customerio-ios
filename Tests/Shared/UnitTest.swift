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
        setUp(enableLogs: false)
    }

    public func setUp(siteId: String? = nil, enableLogs: Bool = false, modifySdkConfig: ((inout SdkConfig) -> Void)? = nil) {
        var newSdkConfig = SdkConfig.Factory.create(siteId: siteId ?? testSiteId, apiKey: "", region: Region.US)
        if enableLogs {
            newSdkConfig.logLevel = CioLogLevel.debug
        }

        modifySdkConfig?(&newSdkConfig)

        diGraph = DIGraph(sdkConfig: newSdkConfig)

        dateUtilStub = DateUtilStub()
        threadUtilStub = ThreadUtilStub()
        // make default behavior of tests to run async code in synchronous way to make tests more predictable.
        diGraph.override(value: threadUtilStub, forType: ThreadUtil.self)

        // Set the default sleep time for retry policy to a small amount to make tests run fast while also testing the
        // HTTP retry policy's real code.
        retryPolicyMock = HttpRetryPolicyMock()
        retryPolicyMock.underlyingNextSleepTime = 0.01

        super.setUp()
    }

    override open func tearDown() {
        Mocks.shared.resetAll()

        deleteAllPersistantData()

        diGraph.reset()

        CustomerIO.resetSharedInstance()

        super.tearDown()
    }

    public func deleteAllPersistantData() {
        deleteKeyValueStorage()
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
