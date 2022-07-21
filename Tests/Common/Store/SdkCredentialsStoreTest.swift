@testable import Common
import Foundation
import SharedTests
import XCTest

class SdkCredentialsStoreTest: UnitTest {
    var keyValueStorageMock = KeyValueStorageMock()

    var store: CIOSdkCredentialsStore!
    var integrationStore: CIOSdkCredentialsStore!

    override func setUp() {
        super.setUp()

        store = CIOSdkCredentialsStore(keyValueStorage: keyValueStorageMock)
        integrationStore = CIOSdkCredentialsStore(keyValueStorage: keyValueStorage)
    }

    // MARK: load

    func test_load_givenNewSiteId_expectNil() {
        keyValueStorageMock.stringReturnValue = nil

        let actual = store.load()

        XCTAssertNil(actual)
    }

    func test_load_givenExistingSiteId_givenMissingRequiredField_expectNil() {
        keyValueStorageMock.stringClosure = { key in
            switch key {
            case .apiKey: return String.random
            default: return nil
            }
        }

        let actual = store.load()

        XCTAssertNil(actual)
    }

    func test_load_givenExistingSiteId_givenExistingCredentials_expectCredentials() {
        let expected = SdkCredentials(
            apiKey: String.random,
            region: Region.EU
        )

        keyValueStorageMock.stringClosure = { key in
            switch key {
            case .apiKey: return expected.apiKey
            case .regionCode: return expected.region.rawValue
            default: return nil
            }
        }

        let actual = store.load()!

        XCTAssertEqual(actual, expected)
    }

    func test_load_expectCacheSetWithLoadedValue() {
        XCTAssertNil(integrationStore.cache)

        let expected = SdkCredentials(apiKey: String.random, region: Region.EU)

        keyValueStorage.setString(expected.apiKey, forKey: .apiKey)
        keyValueStorage.setString(expected.region.rawValue, forKey: .regionCode)

        integrationStore.load()

        XCTAssertNotNil(integrationStore.cache)
        XCTAssertEqual(integrationStore.cache, expected)
    }

    func test_givenSave_expectCacheSetWithNewValue() {
        XCTAssertNil(integrationStore.cache)

        // set random value to load cache with
        keyValueStorage.setString(String.random, forKey: .apiKey)
        keyValueStorage.setString(Region.EU.rawValue, forKey: .regionCode)
        let existingCredentials = integrationStore.load()
        XCTAssertNotNil(existingCredentials)

        let expected = SdkCredentials(apiKey: String.random, region: Region.EU)

        integrationStore.save(expected)

        XCTAssertEqual(integrationStore.cache, expected)
        XCTAssertNotEqual(integrationStore.cache, existingCredentials)
    }
}
