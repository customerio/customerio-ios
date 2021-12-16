@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class KeyValueStorageTests: UnitTest {
    let defaultKey = KeyValueStorageKey.sharedInstanceSiteId
    lazy var defaultStorage: KeyValueStorage = getStorage(siteId: "test")

    private func getStorage(siteId: String) -> KeyValueStorage {
        UserDefaultsKeyValueStorage(siteId: siteId)
    }

    override func setUp() {
        super.setUp()

        defaultStorage.deleteAll()
    }

    // MARK: integration tests

    func test_givenDifferentSites_expectDataSavedSeparatedFromEachOther() {
        let storage1 = getStorage(siteId: String.random)
        let storage2 = getStorage(siteId: String.random)
        // storage3 is UserDefaults.standard. We test this because a customer app might be using it.

        let value = "value-here-for-testing"
        let nextSetValue = "next-set-value"

        storage1.setString(value, forKey: defaultKey)
        storage2.setString(value, forKey: defaultKey)
        UserDefaults.standard.set(value, forKey: defaultKey.rawValue)

        XCTAssertEqual(storage1.string(defaultKey), value)
        XCTAssertEqual(storage2.string(defaultKey), value)
        XCTAssertEqual(UserDefaults.standard.string(forKey: defaultKey.rawValue), value)

        storage1.setString(nextSetValue, forKey: defaultKey)

        XCTAssertEqual(storage1.string(defaultKey), nextSetValue)
        XCTAssertEqual(storage2.string(defaultKey), value)
        XCTAssertEqual(UserDefaults.standard.string(forKey: defaultKey.rawValue), value)
    }

    // MARK: double

    func test_double_givenNotSet_expectNil() {
        let actual = defaultStorage.double(defaultKey)

        XCTAssertNil(actual)
    }

    func test_double_givenSet_expectGetEqualResult() {
        let given: Double = 345566

        defaultStorage.setDouble(given, forKey: defaultKey)

        let expected = given
        let actual = defaultStorage.double(defaultKey)

        XCTAssertEqual(actual, expected)
    }

    // MARK: integer

    func test_integer_givenNotSet_expectNil() {
        let actual = defaultStorage.integer(defaultKey)

        XCTAssertNil(actual)
    }

    func test_integer_givenSet_expectGetEqualResult() {
        let given = 9968686

        defaultStorage.setInt(given, forKey: defaultKey)

        let expected = given
        let actual = defaultStorage.integer(defaultKey)

        XCTAssertEqual(actual, expected)
    }

    // MARK: date

    func test_date_givenNotSet_expectNil() {
        let actual = defaultStorage.date(defaultKey)

        XCTAssertNil(actual)
    }

    func test_date_givenSet_expectGetEqualResult() {
        let given = Date()

        defaultStorage.setDate(given, forKey: defaultKey)

        let expected = given
        let actual = defaultStorage.date(defaultKey)

        XCTAssertEqual(actual?.timeIntervalSince1970, expected.timeIntervalSince1970)
    }

    // MARK: string

    func test_string_givenNotSet_expectNil() {
        let actual = defaultStorage.string(defaultKey)

        XCTAssertNil(actual)
    }

    func test_string_givenSet_expectGetEqualResult() {
        let given = String.random(length: 38)

        defaultStorage.setString(given, forKey: defaultKey)

        let expected = given
        let actual = defaultStorage.string(defaultKey)

        XCTAssertEqual(actual, expected)
    }

    // MARK: deleteAll

    func test_deleteAll_givenNoDataSaved_expectFunctionRuns() {
        let storage = getStorage(siteId: String.random)

        storage.deleteAll()
    }

    func test_deleteAll_givenSavedSomeData_expectDeletesAllData() {
        let value = "value-here-for-testing"

        defaultStorage.setString(value, forKey: defaultKey)

        XCTAssertEqual(defaultStorage.string(defaultKey), value)

        defaultStorage.deleteAll()

        XCTAssertNil(defaultStorage.string(defaultKey))
    }

    func test_deleteAll_givenMultipleSites_expectOnlyDeletesDataFromOneSite() {
        let storage1 = getStorage(siteId: String.random)
        let storage2 = getStorage(siteId: String.random)

        let value = "value-here-for-testing"

        storage1.setString(value, forKey: defaultKey)
        storage2.setString(value, forKey: defaultKey)

        storage1.deleteAll()

        XCTAssertNil(storage1.string(defaultKey))
        XCTAssertEqual(storage2.string(defaultKey), value)
    }
}
