@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class KeyValueStorageTests: UnitTest {
    let defaultKey = KeyValueStorageKey.identifiedProfileId

    var store: UserDefaultsKeyValueStorage {
        UserDefaultsKeyValueStorage()
    }

    // MARK: double

    func test_double_givenNotSet_expectNil() {
        let actual = store.double(defaultKey)

        XCTAssertNil(actual)
    }

    func test_double_givenSet_expectGetEqualResult() {
        let given: Double = 345566

        store.setDouble(given, forKey: defaultKey)

        let expected = given
        let actual = store.double(defaultKey)

        XCTAssertEqual(actual, expected)
    }

    // MARK: integer

    func test_integer_givenNotSet_expectNil() {
        let actual = store.integer(defaultKey)

        XCTAssertNil(actual)
    }

    func test_integer_givenSet_expectGetEqualResult() {
        let given = 9968686

        store.setInt(given, forKey: defaultKey)

        let expected = given
        let actual = store.integer(defaultKey)

        XCTAssertEqual(actual, expected)
    }

    // MARK: date

    func test_date_givenNotSet_expectNil() {
        let actual = store.date(defaultKey)

        XCTAssertNil(actual)
    }

    func test_date_givenSet_expectGetEqualResult() {
        let given = Date()

        store.setDate(given, forKey: defaultKey)

        let expected = given
        let actual = store.date(defaultKey)

        XCTAssertEqual(actual?.timeIntervalSince1970, expected.timeIntervalSince1970)
    }

    // MARK: string

    func test_string_givenNotSet_expectNil() {
        let actual = store.string(defaultKey)

        XCTAssertNil(actual)
    }

    func test_string_givenSet_expectGetEqualResult() {
        let given = String.random(length: 38)

        store.setString(given, forKey: defaultKey)

        let expected = given
        let actual = store.string(defaultKey)

        XCTAssertEqual(actual, expected)
    }

    // MARK: deleteAll

    func test_deleteAll_givenNoDataSaved_expectFunctionRuns() {
        store.deleteAll()
    }

    func test_deleteAll_givenSavedSomeData_expectDeletesAllData() {
        let value = "value-here-for-testing"

        store.setString(value, forKey: defaultKey)

        XCTAssertEqual(store.string(defaultKey), value)

        store.deleteAll()

        XCTAssertNil(store.string(defaultKey))
    }
}
