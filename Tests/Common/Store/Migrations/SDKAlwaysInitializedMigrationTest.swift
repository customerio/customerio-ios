@testable import CioInternalCommon
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class SDKAlwaysInitializedMigrationTest: IntegrationTest {
    private var migration: SDKAlwaysInitializedMigration!

    override func setUp() {
        // Test functions need control over initializing the SDK. Prevent BQ from running so SDK data doesn't get deleted before running migration.
        super.setUp(initializeSdk: false, preventBQFromRunning: true)

        migration = SDKAlwaysInitializedMigration(siteId: String.random, destinationDiGraph: diGraph)
    }

    // MARK: run

    func test_run_givenSDKNotPreviouslyInstalled_expectMigrationToRunSuccessfully() {
        initializeSdk()

        // Because the SDK has never executed, there is no SDK data written that we need to migrate. Run the migration and assert it does not throw any error.

        migration.run()
    }

    func test_run_givenSDKPreviouslyInstalled_expectMigratePreviousSDKData() {
        let profileIdentifiedInSandboxedStorage = String.random
        let deviceTokenInSandboxedStorage = String.random

        // Simulate the SDK was previously installed on a device and added SDK data that will need migrated.
        enableSandboxedStorageInSdk()
        initializeSdk()

        CustomerIO.shared.registerDeviceToken(deviceTokenInSandboxedStorage)
        CustomerIO.shared.identify(identifier: profileIdentifiedInSandboxedStorage)
        CustomerIO.shared.trackMetric(deliveryID: String.random, event: .opened, deviceToken: deviceTokenInSandboxedStorage)
        CustomerIO.shared.profileAttributes = [String.random: String.random]
        let givenNumberOfTasksInQueueBeforeMigration = diGraph.queueStorage.getInventory().count
        disableSandboxedStorageInSdk()
        uninitializeSDK()

        initializeSdk()

        XCTAssertNil(diGraph.profileStore.identifier)
        XCTAssertNil(diGraph.globalDataStore.pushDeviceToken)
        XCTAssertTrue(diGraph.queueStorage.getInventory().isEmpty)

        migration.run()

        XCTAssertEqual(diGraph.profileStore.identifier, profileIdentifiedInSandboxedStorage)
        XCTAssertEqual(diGraph.globalDataStore.pushDeviceToken, deviceTokenInSandboxedStorage)
        XCTAssertEqual(diGraph.queueStorage.getInventory().count, givenNumberOfTasksInQueueBeforeMigration)
    }

    // The SDK could be provided with new data (such as a new device token) before the SDK gets initialized
    // and the migration runs. We need to test that the migration does not overwrite new data in the SDK.
    func test_run_givenSDKPreviouslyInstalled_expectMigrateWithoutOverwritingNewSdkData() {
        let profileIdentifiedInSandboxedStorage = String.random
        let deviceTokenInSandboxedStorage = String.random

        // Simulate the SDK was previously installed on a device and added SDK data that will need migrated.
        initializeSdk()
        enableSandboxedStorageInSdk()
        CustomerIO.shared.registerDeviceToken(deviceTokenInSandboxedStorage)
        CustomerIO.shared.identify(identifier: profileIdentifiedInSandboxedStorage)
        disableSandboxedStorageInSdk()

        let newProfileIdentified = String.random
        let newDeviceToken = String.random
        CustomerIO.shared.registerDeviceToken(newDeviceToken)
        CustomerIO.shared.identify(identifier: newProfileIdentified)

        migration.run()

        XCTAssertEqual(diGraph.profileStore.identifier, newProfileIdentified)
        XCTAssertEqual(diGraph.globalDataStore.pushDeviceToken, newDeviceToken)
    }
}

extension SDKAlwaysInitializedMigrationTest {
    private var numberOfTasksInQueue: Int {
        diGraph.queueStorage.getInventory().count
    }

    private func enableSandboxedStorageInSdk() {
        diGraph.override(value: migration.sandboxedFileStorage, forType: FileStorage.self)
        diGraph.override(value: migration.sandboxedKeyValueStorage, forType: KeyValueStorage.self)
    }

    private func disableSandboxedStorageInSdk() {
        diGraph.reset()
    }

    private func populateSdkWithSdkData() {
        CustomerIO.shared.identify(identifier: String.random)
        CustomerIO.shared.trackMetric(deliveryID: String.random, event: .opened, deviceToken: String.random)
        CustomerIO.shared.registerDeviceToken(String.random)
        CustomerIO.shared.profileAttributes = [String.random: String.random]
    }
}
