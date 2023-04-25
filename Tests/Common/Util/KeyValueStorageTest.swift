@testable import Common
import Foundation
import SharedTests
import XCTest

class KeyValueStorageTests: UnitTest {
    let defaultKey = KeyValueStorageKey.identifiedProfileId
    let deviceMetricsGrabberMock = DeviceMetricsGrabberMock()

    private var storage: UserDefaultsKeyValueStorage {
        diGraph.keyValueStorage as! UserDefaultsKeyValueStorage
    }

    private var globalStorage: UserDefaultsKeyValueStorage {
        let instance = diGraph.keyValueStorage as! UserDefaultsKeyValueStorage
        instance.switchToGlobalDataStore()
        return instance
    }

    private func changeTo(siteId: String) {
        setUp(siteId: siteId)
    }

    // MARK: integration tests

    func test_givenDifferentSites_expectDataSavedSeparatedFromEachOther() {
        let storage1SiteId = String.random
        let storage2SiteId = String.random
        let value = "value-here-for-testing"

        changeTo(siteId: storage1SiteId)
        storage.setString(value, forKey: defaultKey)
        XCTAssertEqual(storage.string(defaultKey), value)

        changeTo(siteId: storage2SiteId)

        XCTAssertNil(storage.string(defaultKey)) // since we changed to a different siteid, we do not expect to see a value here yet.

        changeTo(siteId: storage1SiteId)
        XCTAssertEqual(storage.string(defaultKey), value) // value still exists for the first site id
    }

    // MARK: getFileName

    func test_getFileName_givenGlobalDataStore_expectGetFileNameForGloballyStoredData() {
        let givenAppBundleId = "com.foo.bar"
        deviceMetricsGrabberMock.underlyingAppBundleId = givenAppBundleId
        let storage = UserDefaultsKeyValueStorage(sdkConfig: sdkConfig, deviceMetricsGrabber: deviceMetricsGrabberMock)
        storage.switchToGlobalDataStore()

        XCTAssertEqual(storage.getFileName(), "io.customer.sdk.com.foo.bar.shared")
    }

    func test_getFileName_givenNotGlobalStore_expectGetFileNameForSiteIdStoredData() {
        let givenSiteId = "485895958"
        changeTo(siteId: givenSiteId)
        let givenAppBundleId = "com.foo.bar"
        deviceMetricsGrabberMock.underlyingAppBundleId = givenAppBundleId
        let storage = UserDefaultsKeyValueStorage(sdkConfig: sdkConfig, deviceMetricsGrabber: deviceMetricsGrabberMock)

        XCTAssertEqual(storage.getFileName(), "io.customer.sdk.com.foo.bar.485895958")
    }

    // MARK: double

    func test_double_givenNotSet_expectNil() {
        let actual = storage.double(defaultKey)

        XCTAssertNil(actual)
    }

    func test_double_givenSet_expectGetEqualResult() {
        let given: Double = 345566

        storage.setDouble(given, forKey: defaultKey)

        let expected = given
        let actual = storage.double(defaultKey)

        XCTAssertEqual(actual, expected)
    }

    // MARK: integer

    func test_integer_givenNotSet_expectNil() {
        let actual = storage.integer(defaultKey)

        XCTAssertNil(actual)
    }

    func test_integer_givenSet_expectGetEqualResult() {
        let given = 9968686

        storage.setInt(given, forKey: defaultKey)

        let expected = given
        let actual = storage.integer(defaultKey)

        XCTAssertEqual(actual, expected)
    }

    // MARK: date

    func test_date_givenNotSet_expectNil() {
        let actual = storage.date(defaultKey)

        XCTAssertNil(actual)
    }

    func test_date_givenSet_expectGetEqualResult() {
        let given = Date()

        storage.setDate(given, forKey: defaultKey)

        let expected = given
        let actual = storage.date(defaultKey)

        XCTAssertEqual(actual?.timeIntervalSince1970, expected.timeIntervalSince1970)
    }

    // MARK: string

    func test_string_givenNotSet_expectNil() {
        let actual = storage.string(defaultKey)

        XCTAssertNil(actual)
    }

    func test_string_givenSet_expectGetEqualResult() {
        let given = String.random(length: 38)

        storage.setString(given, forKey: defaultKey)

        let expected = given
        let actual = storage.string(defaultKey)

        XCTAssertEqual(actual, expected)
    }

    // MARK: deleteAll

    func test_deleteAll_givenNoDataSaved_expectFunctionRuns() {
        storage.deleteAll()
    }

    func test_deleteAll_givenSavedSomeData_expectDeletesAllData() {
        let value = "value-here-for-testing"

        storage.setString(value, forKey: defaultKey)

        XCTAssertEqual(storage.string(defaultKey), value)

        storage.deleteAll()

        XCTAssertNil(storage.string(defaultKey))
    }

    func test_deleteAll_givenMultipleSites_expectOnlyDeletesDataFromOneSite() {
        let storage1SiteId = String.random
        let storage2SiteId = String.random
        let value = "value-here-for-testing"

        changeTo(siteId: storage1SiteId)
        storage.setString(value, forKey: defaultKey)

        changeTo(siteId: storage2SiteId)
        storage.setString(value, forKey: defaultKey)

        storage.deleteAll()
        XCTAssertNil(storage.string(defaultKey))

        changeTo(siteId: storage1SiteId)
        XCTAssertEqual(storage.string(defaultKey), value)
    }
}
