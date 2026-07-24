import CioInternalCommon
import SyncSqlCipher

extension StorageManager {
    /// Returns `true` if the event should pass through (not rate-limited).
    /// Returns `false` if the event falls within the rate-limit window.
    ///
    /// The read and write execute on the same serialized connection — the
    /// two-step check-and-update is atomic with respect to all other DB callers.
    func checkAndUpdateRateLimit(
        key: String,
        now: Int64,
        windowSeconds: Int64,
        scope: String
    ) throws -> Bool {
        try db.withConnection { conn in
            if let existing = try conn.fetchOne(AggregationStateRecord.self, id: key),
               now - existing.lastFlushedAt < windowSeconds {
                return false
            }

            try conn.save(AggregationStateRecord(
                ruleId: key,
                stateJson: "{}",
                lastFlushedAt: now,
                scope: scope
            ))
            return true
        }
    }
}
