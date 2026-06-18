import CioInternalCommon
import SyncSqlCipher

private let aggregationConfigKey = "aggregation_config"

extension StorageManager {
    // MARK: - Aggregation Config

    func getAggregationConfig() throws -> String? {
        try getMetaValue(aggregationConfigKey)
    }

    func deleteAggregationConfig() throws {
        try setMetaValue(nil, for: aggregationConfigKey)
    }

    func setAggregationConfig(payload: String) throws {
        try setMetaValue(payload, for: aggregationConfigKey)
    }

    // MARK: - Aggregation State

    func getAggregationState(ruleId: String) throws -> String? {
        try db.fetchOne(AggregationStateRecord.self, id: ruleId)?.stateJson
    }

    func getAggregationLastFlushed(ruleId: String) throws -> Int64? {
        try db.fetchOne(AggregationStateRecord.self, id: ruleId)?.lastFlushedAt
    }

    func setAggregationState(
        ruleId: String,
        stateJSON: String,
        lastFlushedAt: Int64,
        scope: String
    ) throws {
        _ = try db.save(AggregationStateRecord(
            ruleId: ruleId,
            stateJson: stateJSON,
            lastFlushedAt: lastFlushedAt,
            scope: scope
        ))
    }

    func deleteAggregationState(ruleId: String) throws {
        try db.delete(from: AggregationStateRecord.self, id: ruleId)
    }

    /// Clears only profile-scoped accumulator rows. Called on identity reset.
    func deleteProfileScopedAggregationState() throws {
        let scope = col("scope")
        try db.execute(Delete(from: AggregationStateRecord.tableName, where: scope == "profile" || scope.isNull).build())
    }
}

// MARK: - Entity Records

struct AggregationStateRecord: Entity {
    static let tableName = TableName("aggregation_state")
    static let primaryKeyName = "rule_id"
    static let primaryKey: WritableKeyPath<AggregationStateRecord, String> & Sendable = \.ruleId

    var ruleId: String
    var stateJson: String
    var lastFlushedAt: Int64
    var scope: String

    enum CodingKeys: String, CodingKey {
        case ruleId = "rule_id"
        case stateJson = "state_json"
        case lastFlushedAt = "last_flushed_at"
        case scope
    }
}
