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

    override open func setUp() {
        deleteAll()

        super.setUp()
    }

    override open func tearDown() {
        deleteAll()

        diGraph.resetOverrides()

        super.tearDown()
    }

    func deleteAll() {
        deleteKeyValueStorage()
        CustomerIO.resetSharedInstance()
        CioGlobalDataStore().keyValueStorage.deleteAll()
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
