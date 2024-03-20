@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class KeyValueStorageTests: UnitTest {
    let defaultKey = KeyValueStorageKey.identifiedProfileId
    let deviceMetricsGrabberMock = DeviceMetricsGrabberMock()

    var store: SharedKeyValueStorage {
        DIGraphShared.shared.sharedKeyValueStorage
    }

    // MARK: getFileName

    func test_getFileName_expectGetFileName() {
        DIGraphShared.shared.override(value: deviceMetricsGrabberMock, forType: DeviceMetricsGrabber.self)
        let store: UserDefaultsSharedKeyValueStorage? = DIGraphShared.shared.sharedKeyValueStorage as? UserDefaultsSharedKeyValueStorage

        XCTAssertNotNil(store)

        let givenAppBundleId = "com.foo.bar"
        deviceMetricsGrabberMock.underlyingAppBundleId = givenAppBundleId

        XCTAssertEqual(store?.getFileName(), "io.customer.sdk.com.foo.bar.shared")
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
