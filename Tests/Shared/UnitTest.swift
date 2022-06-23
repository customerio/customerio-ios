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
    /**
     Handy objects tests might need to use
     */
    // Prefer to use real instance of key value storage because (1) mocking it is annoying and (2) tests react closely to real app.
    public let testSiteId = "testing"
    public var diGraph: DIGraph {
        DIGraph.getInstance(siteId: testSiteId)
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

    override open func setUp() {
        deleteAll()

        dateUtilStub = DateUtilStub()
        threadUtilStub = ThreadUtilStub()
        // make default behavior of tests to run async code in synchronous way to make tests more predictable.
        diGraph.override(value: threadUtilStub, forType: ThreadUtil.self)

        // Set the default sleep time for retry policy to a small amount to make tests run fast while also testing the HTTP retry policy's real code.
        retryPolicyMock = HttpRetryPolicyMock()
        retryPolicyMock.underlyingNextSleepTime = 0.01

        super.setUp()
    }

    // If logs would help you with debugging a test, enable logs. It's recommended to disable them when running tests as there are so many logs, it's unhelpful.
    // Enabling logs and running 1 test function is helpful.
    public func enableLogs() {
        var sdkConfigStore = diGraph.sdkConfigStore
        var sdkConfig = sdkConfigStore.config
        sdkConfig.logLevel = CioLogLevel.debug
        sdkConfigStore.config = sdkConfig
    }

    override open func tearDown() {
        Mocks.shared.resetAll()

        deleteAll()

        diGraph.reset()

        super.tearDown()
    }

    public func deleteAll() {
        deleteKeyValueStorage()
        CustomerIO.resetSharedInstance()
        CioGlobalDataStore().keyValueStorage.deleteAll()
        deleteAllFiles()
    }

    // function meant to only be in tests as deleting all files from a search path (where app files can be stored!) is not a good idea.
    private func deleteAllFiles() {
        let fileManager = FileManager.default

        let deleteFromSearchPath: (FileManager.SearchPathDirectory) -> Void = { path in
            // OK to use try! here as we want tests to crash if for some reason we are not able to delete files from the device.
            // if files do not get deleted between tests, we could have false positive tests.
            // swiftlint:disable:next force_try
            let pathUrl = try! fileManager.url(for: path, in: .userDomainMask, appropriateFor: nil, create: false)
            // swiftlint:disable:next force_try
            let fileURLs = try! fileManager.contentsOfDirectory(at: pathUrl,
                                                                includingPropertiesForKeys: nil,
                                                                options: .skipsHiddenFiles)
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
        keyValueStorage.deleteAll()
    }

    open func waitForExpectations(file _: StaticString = #file, line _: UInt = #line) {
        waitForExpectations(0.5)
    }
}
