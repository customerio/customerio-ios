@testable import Common
import Foundation
@testable import SharedTests
import XCTest

class SdkCredentialsStoreTest: UnitTest {
    var keyValueStorageMock: KeyValueStorageMock!

    var store: SdkCredentialsStore!
    var integrationStore: SdkCredentialsStore!

    override func setUp() {
        super.setUp()

        keyValueStorageMock = KeyValueStorageMock()

        store = CIOSdkCredentialsStore(keyValueStorage: keyValueStorageMock)
        integrationStore = CIOSdkCredentialsStore(keyValueStorage: keyValueStorage)
    }

    // MARK: sharedInstanceSiteId

    func test_sharedInstanceSiteId_givenSet_expectSaveInCorrectStorageLocation() {
        let givenSiteId = String.random
        keyValueStorageMock.underlyingSharedSiteId = givenSiteId

        store.sharedInstanceSiteId = givenSiteId

        let actual = keyValueStorageMock.setStringSiteIdValueForKeyReceivedArguments?.siteId

        XCTAssertEqual(actual, givenSiteId)
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

    func test_load_givenExistingSiteId_givenExistingCredentials_expectCredentials() {
        let givenSiteId = String.random
        let expected = SdkCredentials(siteId: givenSiteId,
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

    func test_create_expectCredentialsEqualsParameters() {
        let givenSiteId = String.random
        let expected = SdkCredentials(siteId: givenSiteId,
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

    func test_create_save_load_expectCredentialsSameThroughProcess() {
        let givenSiteId = String.random
        let createdCredentials = integrationStore.create(siteId: givenSiteId, apiKey: String.random, region: Region.US)
        integrationStore.save(siteId: givenSiteId, credentials: createdCredentials)

        let actual = integrationStore.load(siteId: givenSiteId)

        XCTAssertNotNil(actual)
        XCTAssertEqual(actual, createdCredentials)
    }

    func test_sharedInstanceSiteId_expectWriteAndReadSameValue() {
        let givenSharedSiteId = String.random

        integrationStore.sharedInstanceSiteId = givenSharedSiteId
        let actual = integrationStore.sharedInstanceSiteId

        XCTAssertEqual(givenSharedSiteId, actual)
    }
}
