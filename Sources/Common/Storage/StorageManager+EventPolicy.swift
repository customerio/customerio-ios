import SyncSqlCipher

extension StorageManager {
    /// Returns `true` if the event should pass through (not rate-limited).
    /// Returns `false` if the event falls within the rate-limit window.
    ///
    /// The read and write execute on the same serialized connection — the
    /// two-step check-and-update is atomic with respect to all other DB callers.
    public func checkAndUpdateRateLimit(
        key: String,
        now: Int64,
        windowSeconds: Int64,
        scope: String
    ) throws -> Bool {
        try db.withConnection { conn in
            let query = Select(col("last_flushed_at"))
                .from("aggregation_state")
                .where(col("rule_id") == key)
                .build()
            let rows = try conn.query(query)

            if let lastSeen = rows.first?.get("last_flushed_at", as: Int64.self),
               now - lastSeen < windowSeconds {
                return false
            }

            try conn.execute(
                """
                INSERT INTO aggregation_state(rule_id, state_json, last_flushed_at, scope)
                 VALUES(?,?,?,?)
                 ON CONFLICT(rule_id) DO UPDATE SET
                  last_flushed_at = excluded.last_flushed_at,
                  scope           = excluded.scope
                """,
                key, "{}", now, scope
            )
            return true
        }
    }
}