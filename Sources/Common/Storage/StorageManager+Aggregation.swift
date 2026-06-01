import SyncSqlCipher

extension StorageManager {

    // MARK: - Aggregation Config

    public func getAggregationConfig() throws -> (payload: String, fetchedAt: String)? {
        let rows = try db.query(
            Select(col("payload"), col("fetched_at"))
                .from("aggregation_rules")
                .where(col("id") == 1)
        )
        guard let row = rows.first,
              let payload = row.get("payload", as: String.self),
              let fetchedAt = row.get("fetched_at", as: String.self)
        else { return nil }
        return (payload: payload, fetchedAt: fetchedAt)
    }

    public func setAggregationConfig(payload: String, fetchedAt: String) throws {
        try db.execute(
            "INSERT INTO aggregation_rules(id, payload, fetched_at) VALUES(1,?,?)"
                + " ON CONFLICT(id) DO UPDATE SET"
                + " payload = excluded.payload,"
                + " fetched_at = excluded.fetched_at",
            payload, fetchedAt
        )
    }

    // MARK: - Aggregation State

    public func getAggregationState(ruleId: String) throws -> String? {
        let rows = try db.query(
            Select(col("state_json"))
                .from("aggregation_state")
                .where(col("rule_id") == ruleId)
        )
        return rows.first?.get("state_json", as: String.self)
    }

    public func getAggregationLastFlushed(ruleId: String) throws -> Int64? {
        let rows = try db.query(
            Select(col("last_flushed_at"))
                .from("aggregation_state")
                .where(col("rule_id") == ruleId)
        )
        return rows.first?.get("last_flushed_at", as: Int64.self)
    }

    public func setAggregationState(
        ruleId: String,
        stateJSON: String,
        lastFlushedAt: Int64,
        scope: String
    ) throws {
        try db.execute(
            """
            INSERT INTO aggregation_state(rule_id, state_json, last_flushed_at, scope)
             VALUES(?,?,?,?)
             ON CONFLICT(rule_id) DO UPDATE SET
              state_json      = excluded.state_json,
              last_flushed_at = excluded.last_flushed_at,
              scope           = excluded.scope
            """,
            ruleId, stateJSON, lastFlushedAt, scope
        )
    }

    public func deleteAggregationState(ruleId: String) throws {
        try db.execute(
            "DELETE FROM aggregation_state WHERE rule_id = ?",
            ruleId
        )
    }

    /// Clears only profile-scoped accumulator rows. Called on identity reset.
    public func deleteProfileScopedAggregationState() throws {
        try db.execute(
            "DELETE FROM aggregation_state WHERE scope = 'profile' OR scope IS NULL"
        )
    }
}