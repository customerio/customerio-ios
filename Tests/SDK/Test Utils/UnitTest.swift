@testable import CIO
import Foundation
import XCTest

class UnitTest: XCTestCase {
    /**
     Handy objects tests might need to use
     */
    // Prefer to use real instance of key value storage because (1) mocking it is annoying and (2) tests react closely to real app.
    let keyValueStorage = DI.shared.keyValueStorage

    override func setUp() {
        deleteAll()

        super.setUp()
    }

    override func tearDown() {
        deleteAll()

        DI.shared.resetOverrides()

        super.tearDown()
    }

    func deleteAll() {
        deleteKeyValueStorage()
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
}
