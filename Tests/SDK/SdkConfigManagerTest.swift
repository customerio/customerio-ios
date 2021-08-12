@testable import CIO
import Foundation
import XCTest

class SdkConfigManagerTest: UnitTest {
    var keyValueStorageMock: KeyValueStorageMock!

    var manager: SdkConfigManager!
    var integrationManager: SdkConfigManager!

    override func setUp() {
        super.setUp()

        keyValueStorageMock = KeyValueStorageMock()
        manager = CIOSdkConfigManager(keyValueStorage: keyValueStorageMock, jsonAdapter: jsonAdapter)
        integrationManager = CIOSdkConfigManager(keyValueStorage: keyValueStorage, jsonAdapter: jsonAdapter)
    }

    // MARK: load

    func test_load_givenNewSiteId_expectNil() {
        let givenSiteId = String.random
        keyValueStorageMock.stringSiteIdForKeyReturnValue = nil

        let actual = manager.load(siteId: givenSiteId)

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

        let actual = manager.load(siteId: givenSiteId)

        XCTAssertNil(actual)
    }

    func test_load_givenExistingSiteId_givenExistingConfig_expectConfig() {
        let givenSiteId = String.random
        let expected = SdkConfig(siteId: givenSiteId,
                                 apiKey: String.random,
                                 region: Region.EU,
                                 devMode: false)

        keyValueStorageMock.stringSiteIdForKeyClosure = { _, key in
            switch key {
            case .apiKey: return expected.apiKey
            case .regionCode: return expected.region.code
            default: return nil
            }
        }

        let actual = manager.load(siteId: givenSiteId)!

        XCTAssertEqual(actual, expected)
    }

    // MARK: create

    func test_create_expectConfigEqualsParameters() {
        let givenSiteId = String.random
        let expected = SdkConfig(siteId: givenSiteId,
                                 apiKey: String.random,
                                 region: Region.EU)

        let actual = manager.create(siteId: givenSiteId, apiKey: expected.apiKey, region: expected.region)

        XCTAssertEqual(actual, expected)
    }

    // MARK: integration tests

    func test_create_load_expectNilBecauseDidNotSave() {
        let givenSiteId = String.random
        _ = integrationManager.create(siteId: givenSiteId, apiKey: String.random, region: Region.US)

        let actual = integrationManager.load(siteId: givenSiteId)

        XCTAssertNil(actual)
    }

    func test_create_save_load_expectConfigSameThroughProcess() {
        let givenSiteId = String.random
        let createdConfig = integrationManager.create(siteId: givenSiteId, apiKey: String.random, region: Region.US)
        integrationManager.save(siteId: givenSiteId, config: createdConfig)

        let actual = integrationManager.load(siteId: givenSiteId)

        XCTAssertNotNil(actual)
        XCTAssertEqual(actual, createdConfig)
    }
}
