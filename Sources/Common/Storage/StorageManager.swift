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
        try db.migrate([CreateSdkMetaSchema(), CreateAggregationTablesSchema()] + extra)
    }

    // MARK: - sdk_meta (utility key/value table)

    public func getMetaValue(_ key: String) throws -> String? {
        try db.fetchOne(SdkMetaRecord.self, id: key)?.value
    }

    public func setMetaValue(_ value: String?, for key: String) throws {
        if let value {
            _ = try db.save(SdkMetaRecord(key: key, value: value))
        } else {
            _ = try db.delete(from: SdkMetaRecord.self, id: key)
        }
    }
}

// MARK: - Schema

private struct CreateSdkMetaSchema: Migration {
    let id = "001-create-sdk-meta"

    func up(_ ctx: MigrationContext) throws {
        try ctx.execute(
            """
            CREATE TABLE IF NOT EXISTS sdk_meta (
                key   TEXT NOT NULL PRIMARY KEY,
                value TEXT NOT NULL
            )
            """
        )
    }

    func down(_ ctx: MigrationContext) throws {}
}

private struct CreateAggregationTablesSchema: Migration {
    let id = "002-create-aggregation-tables"

    func up(_ ctx: MigrationContext) throws {
        // Per-rule accumulator state (counters for rate limiting).
        try ctx.execute(
            """
            CREATE TABLE IF NOT EXISTS aggregation_state (
                rule_id         TEXT    NOT NULL PRIMARY KEY,
                state_json      TEXT    NOT NULL,
                last_flushed_at INTEGER NOT NULL DEFAULT 0,
                scope           TEXT    NOT NULL
            )
            """
        )
    }

    func down(_ ctx: MigrationContext) throws {}
}

// MARK: - Entity Records

private struct SdkMetaRecord: Entity {
    static let tableName = TableName("sdk_meta")
    static let primaryKeyName = "key"
    static let primaryKey: WritableKeyPath<SdkMetaRecord, String> & Sendable = \.key

    var key: String
    var value: String
}
