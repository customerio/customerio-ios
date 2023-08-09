@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class KeyValueStorageTests: UnitTest {
    let defaultKey = KeyValueStorageKey.identifiedProfileId
    let deviceMetricsGrabberMock = DeviceMetricsGrabberMock()

    var defaultStorage: UserDefaultsKeyValueStorage {
        getSiteStorageInstance(siteId: testSiteId)
    }

    private func getSiteStorageInstance(siteId: String, deviceMetricsGrabber: DeviceMetricsGrabber? = nil) -> UserDefaultsKeyValueStorage {
        UserDefaultsKeyValueStorage(
            sdkConfig: SdkConfig.Factory.create(siteId: siteId, apiKey: "", region: .US),
            deviceMetricsGrabber: deviceMetricsGrabber ?? diGraph.deviceMetricsGrabber
        )
    }

    private func getGlobalInstance(deviceMetricsGrabber: DeviceMetricsGrabber? = nil) -> UserDefaultsKeyValueStorage {
        let instance = UserDefaultsKeyValueStorage(
            sdkConfig: SdkConfig.Factory.create(siteId: "", apiKey: "", region: .US),
            deviceMetricsGrabber: deviceMetricsGrabber ?? diGraph.deviceMetricsGrabber
        )
        instance.switchToGlobalDataStore()
        return instance
    }

    // MARK: integration tests

    func test_givenDifferentSites_expectDataSavedSeparatedFromEachOther() {
        let storage1 = getSiteStorageInstance(siteId: String.random)
        let storage2 = getSiteStorageInstance(siteId: String.random)
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

    // MARK: getFileName

    func test_getFileName_givenGlobalDataStore_expectGetFileNameForGloballyStoredData() {
        let givenAppBundleId = "com.foo.bar"
        deviceMetricsGrabberMock.underlyingAppBundleId = givenAppBundleId
        let storage = getGlobalInstance(deviceMetricsGrabber: deviceMetricsGrabberMock)

        XCTAssertEqual(storage.getFileName(), "io.customer.sdk.com.foo.bar.shared")
    }

    func test_getFileName_givenNotGlobalStore_expectGetFileNameForSiteIdStoredData() {
        let givenSiteId = "485895958"
        let givenAppBundleId = "com.foo.bar"
        deviceMetricsGrabberMock.underlyingAppBundleId = givenAppBundleId
        let storage = getSiteStorageInstance(siteId: givenSiteId, deviceMetricsGrabber: deviceMetricsGrabberMock)

        XCTAssertEqual(storage.getFileName(), "io.customer.sdk.com.foo.bar.485895958")
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
        let storage = getSiteStorageInstance(siteId: String.random)

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
        let storage1 = getSiteStorageInstance(siteId: String.random)
        let storage2 = getSiteStorageInstance(siteId: String.random)

        let value = "value-here-for-testing"

        storage1.setString(value, forKey: defaultKey)
        storage2.setString(value, forKey: defaultKey)

        storage1.deleteAll()

        XCTAssertNil(storage1.string(defaultKey))
        XCTAssertEqual(storage2.string(defaultKey), value)
    }
}
