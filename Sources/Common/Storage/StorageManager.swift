import Foundation
@preconcurrency import SyncSqlCipher

/// Gateway for all encrypted on-disk storage used by the aggregation engine.
///
/// Implemented as a `struct` because `SyncSqlCipher.Database` is internally
/// thread-safe (DispatchQueue-serialized), so `StorageManager` carries no
/// mutable state of its own.
public struct StorageManager: Sendable {

    let db: Database

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
        try getString(key, from: "sdk_meta")
    }

    public func setMetaValue(_ value: String?, for key: String) throws {
        try setString(value, for: key, in: "sdk_meta")
    }

    // MARK: - Generic helpers

    func getString(_ key: String, from table: String) throws -> String? {
        let rows = try db.query("SELECT value FROM \(table) WHERE key = ?", key)
        return rows.first?.get("value", as: String.self)
    }

    func setString(_ value: String?, for key: String, in table: String) throws {
        if let value {
            try db.execute(
                "INSERT INTO \(table)(key, value) VALUES(?,?)"
                    + " ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                key, value
            )
        } else {
            try db.execute("DELETE FROM \(table) WHERE key = ?", key)
        }
    }
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
    
    func down(_ ctx: MigrationContext) throws { }
}
