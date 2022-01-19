@testable import CioTracking
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
    public var diGraph: DITracking {
        DITracking.getInstance(siteId: testSiteId)
    }

    public var keyValueStorage: KeyValueStorage {
        diGraph.keyValueStorage
    }

    public var profileStore: ProfileStore {
        diGraph.profileStore
    }

    public var log: ConsoleLogger {
        diGraph.logger as! ConsoleLogger
    }

    public var jsonAdapter: JsonAdapter {
        JsonAdapter(log: log)
    }

    public var retryPolicyMock: HttpRetryPolicyMock!

    public var lockManager: LockManager {
        LockManager()
    }

    override open func setUp() {
        deleteAll()

        retryPolicyMock = HttpRetryPolicyMock()
        retryPolicyMock.underlyingNextSleepTime = 0.01

        super.setUp()
    }

    // If writing integration tests, some dependencies in the DI graph may need credentials to exist to get populated.
    // populate with random values here so your tests can run.
    public func populateSdkCredentials() {
        var credentialsStore = diGraph.sdkCredentialsStore
        credentialsStore.credentials = SdkCredentials(apiKey: String.random, region: Region.US)
    }

    override open func tearDown() {
        TrackingMocks.shared.resetAll()

        deleteAll()

        diGraph.resetOverrides()

        super.tearDown()
    }

    func deleteAll() {
        deleteKeyValueStorage()
        CustomerIO.resetSharedInstance()
        CioGlobalDataStore().keyValueStorage.deleteAll()
        deleteAllFiles()
    }

    // function meant to only be in tests as deleting all files from a search path (where app files can be stored!) is not a good idea.
    private func deleteAllFiles() {
        let fileManager = FileManager.default

        let deleteFromSearchPath: (FileManager.SearchPathDirectory) -> Void = { path in
            let pathUrl = try! fileManager.url(for: path, in: .userDomainMask, appropriateFor: nil, create: false)

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
