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
    public let keyValueStorage = DITracking.shared.keyValueStorage
    public let log: ConsoleLogger = DITracking.shared.logger as! ConsoleLogger
    public var jsonAdapter: JsonAdapter {
        JsonAdapter(log: log)
    }

    override open func setUp() {
        deleteAll()

        super.setUp()
    }

    override open func tearDown() {
        deleteAll()

        DITracking.shared.resetOverrides()

        super.tearDown()
    }

    func deleteAll() {
        deleteKeyValueStorage()
        CustomerIO.resetSharedInstance()
    }

    /**
     Although key value storage is separated by siteId, we want to delete
     common siteId's that we know about.
     */
    func deleteKeyValueStorage() {
        // The SDK does not use `UserDefaults.standard`, but in case a test needs to,
        // let's delete the data for each test.
        UserDefaults.standard.deleteAll()
        keyValueStorage.deleteAll(siteId: keyValueStorage.sharedSiteId)
    }

    open func waitForExpectations(file _: StaticString = #file, line _: UInt = #line) {
        waitForExpectations(0.5)
    }
}
