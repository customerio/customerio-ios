@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class GlobalDataStoreTest: UnitTest {
    private var dataStore: GlobalDataStore!

    override func setUp() {
        super.setUp()

        dataStore = diGraphShared.globalDataStore
    }

    func test_savePushDeviceToken_givenType_expectTokenAndTypeStored() {
        dataStore.savePushDeviceToken("fid-value", type: .fid)

        XCTAssertEqual(dataStore.pushDeviceToken, "fid-value")
        XCTAssertEqual(dataStore.pushDeviceTokenType, .fid)
    }

    func test_savePushDeviceToken_givenSameTokenWithoutType_expectTypeKept() {
        dataStore.savePushDeviceToken("fcm-token", type: .token)

        dataStore.savePushDeviceToken("fcm-token", type: nil)

        XCTAssertEqual(dataStore.pushDeviceToken, "fcm-token")
        XCTAssertEqual(dataStore.pushDeviceTokenType, .token)
    }

    func test_savePushDeviceToken_givenNewTokenWithoutType_expectTypeCleared() {
        dataStore.savePushDeviceToken("fcm-token", type: .token)

        dataStore.savePushDeviceToken("customer-token", type: nil)

        XCTAssertEqual(dataStore.pushDeviceToken, "customer-token")
        XCTAssertNil(dataStore.pushDeviceTokenType)
    }

    func test_savePushDeviceToken_givenSameTokenWithNewType_expectTypeReplaced() {
        dataStore.savePushDeviceToken("value", type: .token)

        dataStore.savePushDeviceToken("value", type: .fid)

        XCTAssertEqual(dataStore.pushDeviceTokenType, .fid)
    }

    func test_pushDeviceTokenType_givenUnknownStoredValue_expectNil() {
        diGraphShared.sharedKeyValueStorage.setString("unknown", forKey: .pushDeviceTokenType)

        XCTAssertNil(dataStore.pushDeviceTokenType)
    }
}
