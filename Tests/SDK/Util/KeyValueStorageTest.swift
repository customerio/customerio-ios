@testable import CIO
import Foundation
import XCTest

class KeyValueStorageIntegrationTests: UnitTest {
    var storage: KeyValueStorage!

    let defaultKey = KeyValueStorageKey.sharedInstanceSiteId

    override func setUp() {
        super.setUp()

        storage = UserDefaultsKeyValueStorage(userDefaults: DI.shared.inject(.userDefaults))
    }

    // MARK: double

    func test_double_givenNotSet_expectNil() {
        let actual = storage.double(forKey: defaultKey)

        XCTAssertNil(actual)
    }

    func test_double_givenSet_expectGetEqualResult() {
        let given: Double = 345566

        storage.setDouble(given, forKey: defaultKey)

        let expected = given
        let actual = storage.double(forKey: defaultKey)

        XCTAssertEqual(actual, expected)
    }

    // MARK: integer

    func test_integer_givenNotSet_expectNil() {
        let actual = storage.integer(forKey: defaultKey)

        XCTAssertNil(actual)
    }

    func test_integer_givenSet_expectGetEqualResult() {
        let given: Int = 9968686

        storage.setInt(given, forKey: defaultKey)

        let expected = given
        let actual = storage.integer(forKey: defaultKey)

        XCTAssertEqual(actual, expected)
    }

    // MARK: date

    func test_date_givenNotSet_expectNil() {
        let actual = storage.date(forKey: defaultKey)

        XCTAssertNil(actual)
    }

    func test_date_givenSet_expectGetEqualResult() {
        let given = Date()

        storage.setDate(given, forKey: defaultKey)

        let expected = given
        let actual = storage.date(forKey: defaultKey)

        XCTAssertEqual(actual?.timeIntervalSince1970, expected.timeIntervalSince1970)
    }

    // MARK: string

    func test_string_givenNotSet_expectNil() {
        let actual = storage.string(forKey: defaultKey)

        XCTAssertNil(actual)
    }

    func test_string_givenSet_expectGetEqualResult() {
        let given = String.random(length: 38)

        storage.setString(given, forKey: defaultKey)

        let expected = given
        let actual = storage.string(forKey: defaultKey)

        XCTAssertEqual(actual, expected)
    }
}
