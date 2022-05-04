@testable import Common
import Foundation
import SharedTests
import XCTest

class GlobalDataStoreTest: UnitTest {
    var store: CioGlobalDataStore!

    override func setUp() {
        super.setUp()

        store = CioGlobalDataStore()
    }

    override func tearDown() {
        super.tearDown()

        store.keyValueStorage.deleteAll()
    }

    // MARK: appendSiteId

    func test_appendSiteId_givenNoSiteIdsAdded_expectAddSiteId() {
        let givenSiteId = String.random

        XCTAssertNil(store.keyValueStorage.string(.allSiteIds))

        store.appendSiteId(givenSiteId)

        XCTAssertEqual(givenSiteId, store.keyValueStorage.string(.allSiteIds))
    }

    func test_appendSiteId_givenAddSameSiteId_expectOnlyAddOnce() {
        let givenSiteId = String.random

        XCTAssertNil(store.keyValueStorage.string(.allSiteIds))

        store.appendSiteId(givenSiteId)
        store.appendSiteId(givenSiteId) // add multiple times

        XCTAssertEqual(givenSiteId, store.keyValueStorage.string(.allSiteIds))
    }

    func test_appendSiteId_givenAddMultipleSiteIds_expectAddAll() {
        let givenSiteId1 = String.random
        let givenSiteId2 = String.random

        XCTAssertNil(store.keyValueStorage.string(.allSiteIds))

        store.appendSiteId(givenSiteId1)
        store.appendSiteId(givenSiteId2)

        // Sets dont have order so much check both orders.
        let expected = [
            "\(givenSiteId1),\(givenSiteId2)",
            "\(givenSiteId2),\(givenSiteId1)"
        ]

        XCTAssertEqualEither(expected,
                             actual: store.keyValueStorage.string(.allSiteIds))
    }
}
