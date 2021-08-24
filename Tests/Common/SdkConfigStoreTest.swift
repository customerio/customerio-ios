@testable import Common
import Foundation
import SharedTests
import XCTest

class SdkCredentialsStoreTest: UnitTest {
    var keyValueStorageMock: KeyValueStorageMock!

    var store: CIOSdkCredentialsStore!
    var integrationStore: CIOSdkCredentialsStore!

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

        let actual = keyValueStorageMock.setStringReceivedArguments?.siteId

        XCTAssertEqual(actual, givenSiteId)
    }

    // MARK: load

    func test_load_givenNewSiteId_expectNil() {
        let givenSiteId = String.random
        keyValueStorageMock.stringReturnValue = nil

        let actual = store.load(siteId: givenSiteId)

        XCTAssertNil(actual)
    }

    func test_load_givenExistingSiteId_givenMissingRequiredField_expectNil() {
        let givenSiteId = String.random

        keyValueStorageMock.stringClosure = { _, key in
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

        keyValueStorageMock.stringClosure = { _, key in
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

    // MARK: save

    func test_save_givenSiteId_expectAppendToAllSiteIds() {
        let givenSiteId = String.random
        let creds = integrationStore.create(siteId: givenSiteId, apiKey: String.random, region: Region.US)

        XCTAssertNil(keyValueStorage.string(siteId: keyValueStorage.sharedSiteId, forKey: .allSiteIds))

        integrationStore.save(siteId: givenSiteId, credentials: creds)

        XCTAssertEqual(givenSiteId, keyValueStorage.string(siteId: keyValueStorage.sharedSiteId, forKey: .allSiteIds))
    }

    // MARK: appendSiteId

    func test_appendSiteId_givenNoSiteIdsAdded_expectAddSiteId() {
        let givenSiteId = String.random

        XCTAssertNil(keyValueStorage.string(siteId: keyValueStorage.sharedSiteId, forKey: .allSiteIds))

        integrationStore.appendSiteId(givenSiteId)

        XCTAssertEqual(givenSiteId, keyValueStorage.string(siteId: keyValueStorage.sharedSiteId, forKey: .allSiteIds))
    }

    func test_appendSiteId_givenAddSameSiteId_expectOnlyAddOnce() {
        let givenSiteId = String.random

        XCTAssertNil(keyValueStorage.string(siteId: keyValueStorage.sharedSiteId, forKey: .allSiteIds))

        integrationStore.appendSiteId(givenSiteId)
        integrationStore.appendSiteId(givenSiteId) // add multiple times

        XCTAssertEqual(givenSiteId, keyValueStorage.string(siteId: keyValueStorage.sharedSiteId, forKey: .allSiteIds))
    }

    func test_appendSiteId_givenAddMultipleSiteIds_expectAddAll() {
        let givenSiteId1 = String.random
        let givenSiteId2 = String.random

        XCTAssertNil(keyValueStorage.string(siteId: keyValueStorage.sharedSiteId, forKey: .allSiteIds))

        integrationStore.appendSiteId(givenSiteId1)
        integrationStore.appendSiteId(givenSiteId2)

        // Sets dont have order so much check both orders.
        let expected = [
            "\(givenSiteId1),\(givenSiteId2)",
            "\(givenSiteId2),\(givenSiteId1)"
        ]

        XCTAssertEqualEither(expected,
                             actual: keyValueStorage.string(siteId: keyValueStorage.sharedSiteId, forKey: .allSiteIds))
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
