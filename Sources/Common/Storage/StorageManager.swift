import Foundation
@preconcurrency import SyncSqlCipher

/// Gateway for all encrypted on-disk storage used by the aggregation engine.
///
/// Implemented as a `struct` because `SyncSqlCipher.Database` is internally
/// thread-safe (DispatchQueue-serialized), so `StorageManager` carries no
/// mutable state of its own.
public struct StorageManager: Sendable {
    // public so per-module StorageManager+X.swift extensions can reach it directly.
    // Restrict to `package` once CocoaPods support is dropped.
    public let db: Database

    public init(db: Database) {
        self.db = db
    }

    /// Apply schema migrations. Must be called once before any other method.
    /// Pass `extra` migrations from modules that extend the schema.
    public func runMigrations(extra: [any Migration] = []) throws {
        try db.migrate([CreateAggregationSchema()] + extra)
    }

    // MARK: - sdk_meta (utility key/value table)

    public func getMetaValue(_ key: String) throws -> String? {
        try db.fetchOne(SdkMetaRecord.self, id: key)?.value
    }

    public func setMetaValue(_ value: String?, for key: String) throws {
        if let value {
            _ = try db.save(SdkMetaRecord(key: key, value: value))
        } else {
            try db.execute("DELETE FROM sdk_meta WHERE key = ?", key)
        }
    }
}

// MARK: - Entity Records

private struct SdkMetaRecord: Entity {
    static let tableName = TableName("sdk_meta")
    static let primaryKeyName = "key"
    static let primaryKey: WritableKeyPath<SdkMetaRecord, String> & Sendable = \.key

    var key: String
    var value: String
}

// MARK: - Schema

private struct CreateAggregationSchema: Migration {
    let id = "001-create-aggregation-schema"

    func up(_ ctx: MigrationContext) throws {
        // Server-fetched aggregation ruleset (single row, id always = 1).
        try ctx.execute(
            """
            CREATE TABLE IF NOT EXISTS aggregation_rules (
                id         INTEGER PRIMARY KEY CHECK (id = 1),
                payload    TEXT    NOT NULL,
                fetched_at TEXT    NOT NULL
            )
            """)
        // Per-rule accumulator state (counters for rate limiting).
        try ctx.execute(
            """
            CREATE TABLE IF NOT EXISTS aggregation_state (
                rule_id         TEXT    NOT NULL PRIMARY KEY,
                state_json      TEXT    NOT NULL,
                last_flushed_at INTEGER NOT NULL DEFAULT 0,
                scope           TEXT    NOT NULL DEFAULT 'profile'
            )
            """)
        // General-purpose SDK key/value metadata.
        try ctx.execute(
            """
            CREATE TABLE IF NOT EXISTS sdk_meta (
                key   TEXT NOT NULL PRIMARY KEY,
                value TEXT NOT NULL
            )
            """)
    }

    func down(_ ctx: MigrationContext) throws {}
}
