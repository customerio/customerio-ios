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
        // and captures the store reference). Pin the directory + store across re-setUp
        // calls within a single test so disk state survives re-initialization.
        if testStore == nil {
            tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            testStore = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: tempDirectory)
        }
        diGraphShared.override(value: testStore, forType: BackgroundDeliveryContextStore.self)

        super.setUpDependencies()
    }

    override open func tearDown() {
        if let dir = tempDirectory { try? FileManager.default.removeItem(at: dir) }
        tempDirectory = nil
        testStore = nil
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

    // MARK: - cdpApiKey persistence

    //
    // `currentCdpApiKey` consults the live provider (DataPipeline) before falling back to
    // disk, so the persistence-level assertions read via a fresh `BackgroundDeliveryContextStore`
    // that hasn't had a provider registered — only the on-disk state is visible.

    private func reloadDiskState() -> BackgroundDeliveryContextStore {
        BackgroundDeliveryContextStore(fileManager: .default, directoryURL: tempDirectory)
    }

    func test_init_givenAllowBackgroundDeliveryDefaultOff_expectCdpApiKeyNotPersisted() {
        // Default config has allowBackgroundDelivery = false, so DataPipeline init must
        // not leave the key on disk.
        XCTAssertNil(reloadDiskState().currentCdpApiKey)
    }

    func test_init_givenAllowBackgroundDeliveryOn_expectCdpApiKeyPersisted() {
        setUp(modifySdkConfig: { config in
            config.allowBackgroundDelivery(true)
        })

        XCTAssertEqual(reloadDiskState().currentCdpApiKey, dataPipelineConfigOptions.cdpApiKey)
    }

    func test_init_givenStalePersistedKey_andAllowBackgroundDeliveryOff_expectKeyCleared() {
        // Simulate a key persisted by a prior launch that had the flag on. Re-init with
        // the flag off must wipe it — otherwise opting out wouldn't actually revoke disk access.
        testStore.setCdpApiKey("stale_key_from_prior_launch")
        XCTAssertEqual(reloadDiskState().currentCdpApiKey, "stale_key_from_prior_launch")

        setUp(modifySdkConfig: nil)

        XCTAssertNil(reloadDiskState().currentCdpApiKey)
    }

    // MARK: - cdpApiKey live provider

    func test_init_expectProviderReturnsInMemoryKeyEvenWhenPersistenceOff() {
        // Default config has allowBackgroundDelivery = false (no disk persistence), but
        // DataPipeline registers itself as the live provider so foreground real-time
        // delivery still works — `currentCdpApiKey` returns the in-memory key.
        XCTAssertNil(reloadDiskState().currentCdpApiKey)
        XCTAssertEqual(testStore.currentCdpApiKey, dataPipelineConfigOptions.cdpApiKey)
    }
}
