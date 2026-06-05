@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
@testable import SharedTests
import XCTest

/// Verifies `DataPipelineImplementation` keeps `BackgroundDeliveryContextStore` in sync with
/// the SDK's identity state. The store is what cold-wake background-delivery code paths
/// (e.g. geofence direct HTTP) read at delivery time without needing the full SDK to be
/// initialized in their process.
class BackgroundDeliveryContextWriteTests: IntegrationTest {
    private var testStore: BackgroundDeliveryContextStore!
    private var tempDirectory: URL!

    override open func setUpDependencies() {
        // Override the DI-resolved store with a temp-directory instance BEFORE
        // initializeSDKComponents runs (which constructs DataPipelineImplementation
        // and captures the store reference).
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        testStore = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: tempDirectory)
        diGraphShared.override(value: testStore, forType: BackgroundDeliveryContextStore.self)

        super.setUpDependencies()
    }

    override open func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: - apiHost

    func test_init_expectApiHostSnapshottedFromModuleConfig() {
        XCTAssertEqual(testStore.currentApiHost, dataPipelineConfigOptions.apiHost)
    }

    // MARK: - identify

    func test_identify_expectUserIdWrittenToStore() {
        let givenIdentifier = String.random

        customerIO.identify(userId: givenIdentifier)

        XCTAssertEqual(testStore.currentUserId, givenIdentifier)
    }

    func test_identify_givenChangingUser_expectStoreReflectsLatest() {
        customerIO.identify(userId: "user_a")
        XCTAssertEqual(testStore.currentUserId, "user_a")

        customerIO.identify(userId: "user_b")
        XCTAssertEqual(testStore.currentUserId, "user_b")
    }

    // MARK: - clearIdentify

    func test_clearIdentify_givenIdentifiedProfile_expectUserIdClearedFromStore() {
        customerIO.identify(userId: "user_42")
        XCTAssertEqual(testStore.currentUserId, "user_42")

        customerIO.clearIdentify()

        XCTAssertNil(testStore.currentUserId)
        XCTAssertNil(analytics.userId)
    }
}
