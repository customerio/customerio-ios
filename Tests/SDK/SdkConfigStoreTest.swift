@testable import CIO
import Foundation
import XCTest

class SdkConfigStoreTest: UnitTest {
    var keyValueStorageMock: KeyValueStorageMock!

    var store: SdkConfigStore!
    var integrationStore: SdkConfigStore!

    override func setUp() {
        super.setUp()

        keyValueStorageMock = KeyValueStorageMock()

        store = CIOSdkConfigStore(keyValueStorage: keyValueStorageMock)
        integrationStore = CIOSdkConfigStore(keyValueStorage: keyValueStorage)
    }

    // MARK: load

    func test_load_givenNewSiteId_expectNil() {
        let givenSiteId = String.random
        keyValueStorageMock.stringSiteIdForKeyReturnValue = nil

        let actual = store.load(siteId: givenSiteId)

        XCTAssertNil(actual)
    }

    func test_load_givenExistingSiteId_givenMissingRequiredField_expectNil() {
        let givenSiteId = String.random

        keyValueStorageMock.stringSiteIdForKeyClosure = { _, key in
            switch key {
            case .apiKey: return String.random
            default: return nil
            }
        }

        let actual = store.load(siteId: givenSiteId)

        XCTAssertNil(actual)
    }

    func test_load_givenExistingSiteId_givenExistingConfig_expectConfig() {
        let givenSiteId = String.random
        let expected = SdkConfig(siteId: givenSiteId,
                                 apiKey: String.random,
                                 region: Region.EU)

        keyValueStorageMock.stringSiteIdForKeyClosure = { _, key in
            switch key {
            case .apiKey: return expected.apiKey
            case .regionCode: return expected.region.rawValue
            default: return nil
            }
        }

        let actual = store.load(siteId: givenSiteId)!

        XCTAssertEqual(actual, expected)
    }

    // MARK: create

    func test_create_expectConfigEqualsParameters() {
        let givenSiteId = String.random
        let expected = SdkConfig(siteId: givenSiteId,
                                 apiKey: String.random,
                                 region: Region.EU)

        let actual = store.create(siteId: givenSiteId, apiKey: expected.apiKey, region: expected.region)

        XCTAssertEqual(actual, expected)
    }

    // MARK: integration tests

    func test_create_load_expectNilBecauseDidNotSave() {
        let givenSiteId = String.random
        _ = integrationStore.create(siteId: givenSiteId, apiKey: String.random, region: Region.US)

        let actual = integrationStore.load(siteId: givenSiteId)

        XCTAssertNil(actual)
    }

    func test_create_save_load_expectConfigSameThroughProcess() {
        let givenSiteId = String.random
        let createdConfig = integrationStore.create(siteId: givenSiteId, apiKey: String.random, region: Region.US)
        integrationStore.save(siteId: givenSiteId, config: createdConfig)

        let actual = integrationStore.load(siteId: givenSiteId)

        XCTAssertNotNil(actual)
        XCTAssertEqual(actual, createdConfig)
    }
}
