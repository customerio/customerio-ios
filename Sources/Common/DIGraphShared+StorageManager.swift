import Foundation
import SyncSqlCipher

public extension DIGraphShared {
    /// Creates, migrates, and registers the ``StorageManager`` for a given CDP API key.
    ///
    /// Follows the same pattern as ``registerPendingPushDeliveryStore(appGroupId:)``
    /// — call this once from ``DataPipeline.initialize(moduleConfig:)`` before
    /// creating ``DataPipelineImplementation``, so the graph has a live instance
    /// ready for any code that calls ``storageManager``.
    ///
    /// Returns `nil` and logs an error if the database cannot be opened or
    /// migrations fail. Callers that depend on storage must handle a nil result
    /// gracefully; the aggregation engine will be a no-op in that case.
    @discardableResult
    func registerStorageManager(cdpApiKey: String) -> StorageManager? {
        do {
            let path = Self.databasePath(for: cdpApiKey)
            let dbKey = try dbKeyProvider.getOrCreateDbKey(account: cdpApiKey)
            let db = try Database(path: path, key: dbKey)
            let storage = StorageManager(db: db)
            try storage.runMigrations()
            register(storage, forType: StorageManager.self)
            return storage
        } catch {
            logger.error("CIO StorageManager failed to initialize: \(error)")
            return nil
        }
    }

    /// The registered ``StorageManager``, or `nil` if ``registerStorageManager(cdpApiKey:)``
    /// has not been called yet or failed.
    var storageManager: StorageManager? {
        getOptional(StorageManager.self)
    }

    private static func databasePath(for cdpApiKey: String) -> String {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport
            .appendingPathComponent("io.customer", isDirectory: true)
            .appendingPathComponent(cdpApiKey, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cio.db").path
    }
}
