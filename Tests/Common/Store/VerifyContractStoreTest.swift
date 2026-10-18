// Contract: cio-sdk-tools `verify push` reads these on-disk stores, names and keys (its `docs/verify-contract.md`).
// Renaming any of them breaks it.

@testable import CioInternalCommon
@testable import CioInternalCommonMocks
import Foundation
import SharedTests
import XCTest

class VerifyContractStoreTest: UnitTest {
    private let deviceMetricsGrabberMock = DeviceMetricsGrabberMock()
    private let givenBundleId = "io.customer.contract-test.\(UUID().uuidString)"

    private var contextFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("io.customer.sdk.background")
            .appendingPathComponent("delivery_context.json")
    }

    override func setUp() {
        super.setUp()

        mockCollection.add(mock: deviceMetricsGrabberMock)
        deviceMetricsGrabberMock.underlyingAppBundleId = givenBundleId
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: "io.customer.sdk.\(givenBundleId).shared")
        // The base class deletes everything in Application Support, `delivery_context.json` included.
        super.tearDown()
    }

    // MARK: pushDeviceToken

    func test_pushDeviceToken_expectStoredUnderKeyInSdkSharedSuite() {
        let store = CioSharedDataStore(
            keyValueStorage: UserDefaultsSharedKeyValueStorage(deviceMetricsGrabber: deviceMetricsGrabberMock)
        )

        store.pushDeviceToken = "abcd1234"

        let suite = UserDefaults(suiteName: "io.customer.sdk.\(givenBundleId).shared")
        XCTAssertEqual(suite?.string(forKey: "pushDeviceToken"), "abcd1234")
    }

    // MARK: delivery_context.json

    func test_deliveryContext_expectUserIdInJsonFileInApplicationSupport() throws {
        let store = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: nil)

        store.setUserId("u-42")

        let data = try Data(contentsOf: contextFileURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["userId"] as? String, "u-42")
    }
}
