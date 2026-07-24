@testable import CioDataPipelines
@testable import CioInternalCommon
import SyncSqlCipher
import XCTest

class DataPipelineClearIdentifyTests: UnitTest {
    private var testStorage: StorageManager!

    override func setUpDependencies() {
        let db = try! Database(path: ":memory:", key: "testkey", walMode: false)
        testStorage = StorageManager(db: db)
        try! testStorage.runMigrations()
        diGraphShared.override(value: testStorage, forType: StorageManager.self)
        super.setUpDependencies()
    }

    // MARK: - Profile-scoped state

    func test_clearIdentify_deletesProfileScopedRateLimitEntries() throws {
        try testStorage.setAggregationState(
            ruleId: "profile-rule", stateJSON: "{}", lastFlushedAt: 0, scope: "profile"
        )

        customerIO.clearIdentify()

        XCTAssertNil(try testStorage.getAggregationState(ruleId: "profile-rule"))
    }

    func test_clearIdentify_preservesDeviceScopedRateLimitEntries() throws {
        try testStorage.setAggregationState(
            ruleId: "device-rule", stateJSON: "{}", lastFlushedAt: 0, scope: "device"
        )

        customerIO.clearIdentify()

        XCTAssertNotNil(try testStorage.getAggregationState(ruleId: "device-rule"))
    }

    func test_clearIdentify_deletesProfileEntries_preservesDeviceEntries() throws {
        try testStorage.setAggregationState(
            ruleId: "profile-rule", stateJSON: "{}", lastFlushedAt: 0, scope: "profile"
        )
        try testStorage.setAggregationState(
            ruleId: "device-rule", stateJSON: "{}", lastFlushedAt: 0, scope: "device"
        )

        customerIO.clearIdentify()

        XCTAssertNil(try testStorage.getAggregationState(ruleId: "profile-rule"))
        XCTAssertNotNil(try testStorage.getAggregationState(ruleId: "device-rule"))
    }

    func test_clearIdentify_withNoStorageEntries_doesNotThrow() {
        XCTAssertNoThrow(customerIO.clearIdentify())
    }
}
