import Foundation
@_exported @preconcurrency import SyncSqlCipher

/// Gateway for all encrypted on-disk storage used by the aggregation engine.
///
/// Implemented as a `struct` because `SyncSqlCipher.Database` is internally
/// thread-safe (DispatchQueue-serialized), so `StorageManager` carries no
/// mutable state of its own.
public struct StorageManager: Sendable {
    // public so per-module StorageManager+X.swift extensions can reach it directly.
    // Restrict to `package` once CocoaPods support is dropped.
    public let db: Database
    /// The CDP API key this instance was opened with. Used to detect key mismatches
    /// when a recovered instance is already registered in the DI graph.
    public let cdpApiKey: String

    public init(db: Database, cdpApiKey: String) {
        self.db = db
        self.cdpApiKey = cdpApiKey
    }

    /// Apply schema migrations. Must be called once before any other method.
    /// Pass `extra` migrations from modules that extend the schema.
    public func runMigrations(extra: [any Migration] = []) throws {
        try db.migrate([CreateSdkMetaSchema(), CreateLiveActivityTokensSchema()] + extra)
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

// MARK: - Entity Records

private struct SdkMetaRecord: Entity {
    static let tableName = TableName("sdk_meta")
    static let primaryKeyName = "key"
    static let primaryKey: WritableKeyPath<SdkMetaRecord, String> & Sendable = \.key

    var key: String
    var value: String
}
