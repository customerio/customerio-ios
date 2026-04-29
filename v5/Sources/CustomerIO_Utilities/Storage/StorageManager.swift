import Foundation
import SqlCipherKit

/// Gateway for all encrypted on-disk storage.
/// All SqlCipher I/O must go through this type — nothing reads or writes the
/// database directly.
///
/// Implemented as a `struct` rather than an `actor` because `StorageManager`
/// has no mutable state of its own — the single stored property `db` is a
/// `let`. Concurrency safety is fully provided by `Database`, which is itself
/// an actor. `StorageManager` is automatically `Sendable` because `Database`
/// (an actor) is `Sendable`.
public struct StorageManager: Sendable {

    /// Exposed at `package` access so module-specific extensions (in
    /// `CustomerIO`, `CustomerIO_Geofencing`, etc.) can add typed query
    /// methods without making the raw database handle part of the public API.
    package let db: Database

    public init(db: Database) {
        self.db = db
    }

    // MARK: - Schema Bootstrap

    /// Apply schema migrations. Must be called once before any other method.
    /// Pass `extra` migrations from modules that manage their own tables
    /// (e.g. `LocationStorageMigration`). They run after the core schema.
    public func runMigrations(extra: [any Migration] = []) async throws {
        try await db.migrate([CreateSDKSchema()] + extra)
    }

    // MARK: - Key/Value (identity, device, sdk_meta)

    public func getString(_ key: String, from table: String) async throws -> String? {
        try await db.scalarQuery(
            "SELECT value FROM \(table) WHERE key = ?",
            key,
            as: String.self
        )
    }

    /// Upsert a value, or delete the row when `value` is nil.
    public func setString(_ value: String?, for key: String, in table: String) async throws {
        if let value {
            try await db.execute(
                "INSERT INTO \(table)(key, value) VALUES(?,?)"
                    + " ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                key, value
            )
        } else {
            try await db.execute("DELETE FROM \(table) WHERE key = ?", key)
        }
    }

    // MARK: - sdk_meta helpers

    public func getMetaValue(_ key: String) async throws -> String? {
        try await getString(key, from: "sdk_meta")
    }

    public func setMetaValue(_ value: String?, for key: String) async throws {
        try await setString(value, for: key, in: "sdk_meta")
    }
}

// MARK: - Schema Migrations

private struct CreateSDKSchema: Migration {
    let id = "001-create-sdk-schema"

    func up(_ ctx: MigrationContext) throws {
        // Profile ID and anonymous ID
        try ctx.execute(
            """
            CREATE TABLE IF NOT EXISTS identity (
                key   TEXT NOT NULL PRIMARY KEY,
                value TEXT NOT NULL
            )
            """)
        // Push token and device attributes
        try ctx.execute(
            """
            CREATE TABLE IF NOT EXISTS device (
                key   TEXT NOT NULL PRIMARY KEY,
                value TEXT
            )
            """)
        // Pending upload events (JSON-serialised EnrichedEvent)
        try ctx.execute(
            """
            CREATE TABLE IF NOT EXISTS event_queue (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                payload     TEXT    NOT NULL,
                enqueued_at TEXT    NOT NULL DEFAULT (datetime('now'))
            )
            """)
        // Server-fetched aggregation ruleset (single row, id always = 1)
        try ctx.execute(
            """
            CREATE TABLE IF NOT EXISTS aggregation_rules (
                id         INTEGER PRIMARY KEY CHECK (id = 1),
                payload    TEXT    NOT NULL,
                fetched_at TEXT    NOT NULL
            )
            """)
        // In-progress accumulator values, keyed by rule_id
        try ctx.execute(
            """
            CREATE TABLE IF NOT EXISTS aggregation_state (
                rule_id         TEXT    NOT NULL PRIMARY KEY,
                state_json      TEXT    NOT NULL,
                last_flushed_at INTEGER NOT NULL DEFAULT 0,
                scope           TEXT    NOT NULL DEFAULT 'profile'
            )
            """)
        // SDK flags and timestamps (version, install date, migration flags)
        try ctx.execute(
            """
            CREATE TABLE IF NOT EXISTS sdk_meta (
                key   TEXT NOT NULL PRIMARY KEY,
                value TEXT NOT NULL
            )
            """)
    }

    func down(_ ctx: MigrationContext) throws {
        for table in [
            "identity", "device", "event_queue",
            "aggregation_rules", "aggregation_state", "sdk_meta",
        ] {
            try ctx.execute("DROP TABLE IF EXISTS \(table)")
        }
    }
}

// MARK: - Errors

public enum StorageError: Error {
    case invalidRow
}
