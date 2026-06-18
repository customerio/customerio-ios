@testable import CioDataPipelines
import CioInternalCommon
import SyncSqlCipher
import XCTest

class StorageManagerAggregationTests: XCTestCase {
    private var storage: StorageManager!

    override func setUp() {
        super.setUp()
        let db = try! Database(path: ":memory:", key: "testkey", walMode: false)
        storage = StorageManager(db: db)
        try! storage.runMigrations()
    }

    // MARK: - Aggregation config

    func test_getAggregationConfig_whenEmpty_returnsNil() throws {
        XCTAssertNil(try storage.getAggregationConfig())
    }

    func test_setAndGetAggregationConfig_roundTrip() throws {
        try storage.setAggregationConfig(payload: #"{"filters":[]}"#)

        let result = try XCTUnwrap(storage.getAggregationConfig())
        XCTAssertEqual(result, #"{"filters":[]}"#)
    }

    func test_setAggregationConfig_upsert_overwritesPreviousValue() throws {
        try storage.setAggregationConfig(payload: #"{"filters":[]}"#)
        try storage.setAggregationConfig(payload: #"{"rateLimits":[]}"#)

        let result = try XCTUnwrap(storage.getAggregationConfig())
        XCTAssertEqual(result, #"{"rateLimits":[]}"#)
    }

    // MARK: - Aggregation state

    func test_getAggregationState_whenEmpty_returnsNil() throws {
        XCTAssertNil(try storage.getAggregationState(ruleId: "rule-1"))
    }

    func test_getAggregationLastFlushed_whenEmpty_returnsNil() throws {
        XCTAssertNil(try storage.getAggregationLastFlushed(ruleId: "rule-1"))
    }

    func test_setAndGetAggregationState_roundTrip() throws {
        try storage.setAggregationState(
            ruleId: "rule-1",
            stateJSON: #"{"count":5}"#,
            lastFlushedAt: 1716854400,
            scope: "profile"
        )

        XCTAssertEqual(try storage.getAggregationState(ruleId: "rule-1"), #"{"count":5}"#)
        XCTAssertEqual(try storage.getAggregationLastFlushed(ruleId: "rule-1"), 1716854400)
    }

    func test_setAggregationState_upsert_updatesExistingRow() throws {
        try storage.setAggregationState(
            ruleId: "rule-1", stateJSON: #"{"count":1}"#, lastFlushedAt: 100, scope: "profile"
        )
        try storage.setAggregationState(
            ruleId: "rule-1", stateJSON: #"{"count":9}"#, lastFlushedAt: 999, scope: "profile"
        )

        XCTAssertEqual(try storage.getAggregationState(ruleId: "rule-1"), #"{"count":9}"#)
        XCTAssertEqual(try storage.getAggregationLastFlushed(ruleId: "rule-1"), 999)
    }

    func test_multipleRules_stateIsIsolatedByRuleId() throws {
        try storage.setAggregationState(
            ruleId: "rule-A", stateJSON: #"{"count":1}"#, lastFlushedAt: 0, scope: "profile"
        )
        try storage.setAggregationState(
            ruleId: "rule-B", stateJSON: #"{"count":99}"#, lastFlushedAt: 0, scope: "device"
        )

        XCTAssertEqual(try storage.getAggregationState(ruleId: "rule-A"), #"{"count":1}"#)
        XCTAssertEqual(try storage.getAggregationState(ruleId: "rule-B"), #"{"count":99}"#)
    }

    // MARK: - Delete

    func test_deleteAggregationState_removesTargetedRule() throws {
        try storage.setAggregationState(
            ruleId: "rule-1", stateJSON: "{}", lastFlushedAt: 0, scope: "profile"
        )
        try storage.setAggregationState(
            ruleId: "rule-2", stateJSON: "{}", lastFlushedAt: 0, scope: "profile"
        )

        try storage.deleteAggregationState(ruleId: "rule-1")

        XCTAssertNil(try storage.getAggregationState(ruleId: "rule-1"))
        XCTAssertNotNil(try storage.getAggregationState(ruleId: "rule-2"))
    }

    func test_deleteAggregationState_onNonExistentRule_doesNotThrow() throws {
        XCTAssertNoThrow(try storage.deleteAggregationState(ruleId: "nonexistent"))
    }

    func test_deleteProfileScopedAggregationState_removesProfileRules_preservesDeviceRules() throws {
        try storage.setAggregationState(
            ruleId: "profile-rule", stateJSON: "{}", lastFlushedAt: 0, scope: "profile"
        )
        try storage.setAggregationState(
            ruleId: "device-rule", stateJSON: "{}", lastFlushedAt: 0, scope: "device"
        )

        try storage.deleteProfileScopedAggregationState()

        XCTAssertNil(try storage.getAggregationState(ruleId: "profile-rule"))
        XCTAssertNotNil(try storage.getAggregationState(ruleId: "device-rule"))
    }
}
