@testable import Common
import Foundation
import XCTest

class KeyValueStorageTests: UnitTest {
    var storage: KeyValueStorage = UserDefaultsKeyValueStorage()

    let defaultKey = KeyValueStorageKey.sharedInstanceSiteId
    let defaultSiteId = "12345"

    override func setUp() {
        super.setUp()

        storage.deleteAll(siteId: defaultSiteId)
    }

    // MARK: integration tests

    func test_givenDifferentSites_expectDataSavedSeparatedFromEachOther() {
        let siteId1 = String.random
        let siteId2 = String.random
        // site3 is UserDefaults.standard. We test this because a customer app might be using it.

        let value = "value-here-for-testing"
        let nextSetValue = "next-set-value"

        storage.setString(siteId: siteId1, value: value, forKey: defaultKey)
        storage.setString(siteId: siteId2, value: value, forKey: defaultKey)
        UserDefaults.standard.set(value, forKey: defaultKey.rawValue)

        XCTAssertEqual(storage.string(siteId: siteId1, forKey: defaultKey), value)
        XCTAssertEqual(storage.string(siteId: siteId2, forKey: defaultKey), value)
        XCTAssertEqual(UserDefaults.standard.string(forKey: defaultKey.rawValue), value)

        storage.setString(siteId: siteId1, value: nextSetValue, forKey: defaultKey)

        XCTAssertEqual(storage.string(siteId: siteId1, forKey: defaultKey), nextSetValue)
        XCTAssertEqual(storage.string(siteId: siteId2, forKey: defaultKey), value)
        XCTAssertEqual(UserDefaults.standard.string(forKey: defaultKey.rawValue), value)
    }

    // MARK: double

    func test_double_givenNotSet_expectNil() {
        let actual = storage.double(siteId: defaultSiteId, forKey: defaultKey)

        XCTAssertNil(actual)
    }

    func test_double_givenSet_expectGetEqualResult() {
        let given: Double = 345566

        storage.setDouble(siteId: defaultSiteId, value: given, forKey: defaultKey)

        let expected = given
        let actual = storage.double(siteId: defaultSiteId, forKey: defaultKey)

        XCTAssertEqual(actual, expected)
    }

    // MARK: integer

    func test_integer_givenNotSet_expectNil() {
        let actual = storage.integer(siteId: defaultSiteId, forKey: defaultKey)

        XCTAssertNil(actual)
    }

    func test_integer_givenSet_expectGetEqualResult() {
        let given: Int = 9968686

        storage.setInt(siteId: defaultSiteId, value: given, forKey: defaultKey)

        let expected = given
        let actual = storage.integer(siteId: defaultSiteId, forKey: defaultKey)

        XCTAssertEqual(actual, expected)
    }

    // MARK: date

    func test_date_givenNotSet_expectNil() {
        let actual = storage.date(siteId: defaultSiteId, forKey: defaultKey)

        XCTAssertNil(actual)
    }

    func test_date_givenSet_expectGetEqualResult() {
        let given = Date()

        storage.setDate(siteId: defaultSiteId, value: given, forKey: defaultKey)

        let expected = given
        let actual = storage.date(siteId: defaultSiteId, forKey: defaultKey)

        XCTAssertEqual(actual?.timeIntervalSince1970, expected.timeIntervalSince1970)
    }

    // MARK: string

    func test_string_givenNotSet_expectNil() {
        let actual = storage.string(siteId: defaultSiteId, forKey: defaultKey)

        XCTAssertNil(actual)
    }

    func test_string_givenSet_expectGetEqualResult() {
        let given = String.random(length: 38)

        storage.setString(siteId: defaultSiteId, value: given, forKey: defaultKey)

        let expected = given
        let actual = storage.string(siteId: defaultSiteId, forKey: defaultKey)

        XCTAssertEqual(actual, expected)
    }

    // MARK: deleteAll

    func test_deleteAll_givenNoDataSaved_expectFunctionRuns() {
        let siteId = String.random

        storage.deleteAll(siteId: siteId)
    }

    func test_deleteAll_givenSavedSomeData_expectDeletesAllData() {
        let siteId = String.random

        let value = "value-here-for-testing"

        storage.setString(siteId: siteId, value: value, forKey: defaultKey)

        XCTAssertEqual(storage.string(siteId: siteId, forKey: defaultKey), value)

        storage.deleteAll(siteId: siteId)

        XCTAssertNil(storage.string(siteId: siteId, forKey: defaultKey))
    }

    func test_deleteAll_givenMultipleSites_expectOnlyDeletesDataFromOneSite() {
        let siteId1 = String.random
        let siteId2 = String.random

        let value = "value-here-for-testing"

        storage.setString(siteId: siteId1, value: value, forKey: defaultKey)
        storage.setString(siteId: siteId2, value: value, forKey: defaultKey)

        storage.deleteAll(siteId: siteId1)

        XCTAssertNil(storage.string(siteId: siteId1, forKey: defaultKey))
        XCTAssertEqual(storage.string(siteId: siteId2, forKey: defaultKey), value)
    }
}
