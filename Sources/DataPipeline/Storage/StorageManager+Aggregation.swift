import CioInternalCommon
import SyncSqlCipher

extension StorageManager {
    // MARK: - Aggregation Config

    func getAggregationConfig() throws -> (payload: String, fetchedAt: String)? {
        guard let record = try db.fetchOne(AggregationRulesRecord.self, id: 1) else { return nil }
        return (payload: record.payload, fetchedAt: record.fetchedAt)
    }

    func deleteAggregationConfig() throws {
        try db.execute("DELETE FROM aggregation_rules WHERE id = 1")
    }

    func setAggregationConfig(payload: String, fetchedAt: String) throws {
        _ = try db.save(AggregationRulesRecord(payload: payload, fetchedAt: fetchedAt))
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
        try db.execute("DELETE FROM aggregation_state WHERE rule_id = ?", ruleId)
    }

    /// Clears only profile-scoped accumulator rows. Called on identity reset.
    func deleteProfileScopedAggregationState() throws {
        try db.execute("DELETE FROM aggregation_state WHERE scope = 'profile' OR scope IS NULL")
    }
}

// MARK: - Entity Records

private struct AggregationRulesRecord: Entity {
    static let tableName = TableName("aggregation_rules")
    static let primaryKey: WritableKeyPath<AggregationRulesRecord, Int> & Sendable = \.id

    var id: Int = 1
    var payload: String
    var fetchedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case payload
        case fetchedAt = "fetched_at"
    }
}

private struct AggregationStateRecord: Entity {
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
