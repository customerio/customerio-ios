import Foundation
import SyncSqlCipher

public extension DIGraphShared {
    /// Creates, migrates, and registers the ``StorageManager`` for a given CDP API key,
    /// then persists the key to disk so ``restoredStorageManager`` can reconstruct it
    /// on a future cold-boot background wake.
    ///
    /// Returns `nil` and logs an error if the database cannot be opened or migrations fail.
    @discardableResult
    func registerStorageManager(cdpApiKey: String) -> StorageManager? {
        getOrCreate(of: StorageManager.self, matching: { $0.cdpApiKey == cdpApiKey }) {
            guard let storage = makeStorageManager(cdpApiKey: cdpApiKey) else { return nil }
            Self.writeStoredApiKey(cdpApiKey)
            return storage
        }
    }

    /// The registered ``StorageManager``, or `nil` if ``registerStorageManager(cdpApiKey:)``
    /// has not been called yet or failed.
    var storageManager: StorageManager? {
        getOptional(StorageManager.self)
    }

    /// Returns the registered ``StorageManager`` if available, or attempts to recover one
    /// from the API key written to disk by a previous call to ``registerStorageManager(cdpApiKey:)``.
    ///
    /// Intended for background-wake entry points (e.g. cross-platform push handlers) where the
    /// normal SDK initialization has not run in the current process. The recovered instance is
    /// stored in the graph so subsequent callers receive the same object. Returns `nil` only on
    /// first boot (no key file exists) or if the database cannot be opened.
    var restoredStorageManager: StorageManager? {
        getOrCreate(of: StorageManager.self) {
            guard let key = Self.readStoredApiKey() else { return nil }
            return makeStorageManager(cdpApiKey: key)
        }
    }

    // MARK: - Private helpers

    private func makeStorageManager(cdpApiKey: String) -> StorageManager? {
        do {
            let path = Self.databasePath(for: cdpApiKey)
            let encryptionKey = try dbKeyProvider.getOrCreateDbKey(account: cdpApiKey)
            let db = try Database(path: path, key: encryptionKey)
            let storage = StorageManager(db: db, cdpApiKey: cdpApiKey)
            try storage.runMigrations()
            return storage
        } catch {
            logger.error("CIO StorageManager failed to initialize: \(error)")
            return nil
        }
    }

    private static func databasePath(for cdpApiKey: String) -> String {
        let dir = storageDirectory(for: cdpApiKey)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cio.db").path
    }

    private static func storageDirectory(for cdpApiKey: String) -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("io.customer", isDirectory: true)
            .appendingPathComponent(cdpApiKey, isDirectory: true)
    }

    private static var apiKeySidecarURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("io.customer", isDirectory: true)
            .appendingPathComponent("cio-api-key")
    }

    private static func writeStoredApiKey(_ key: String) {
        let sidecar = apiKeySidecarURL
        try? FileManager.default.createDirectory(
            at: sidecar.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // .atomic write goes to a temp file then renames, so a crash mid-write cannot corrupt the file.
        try? key.data(using: .utf8)?.write(to: sidecar, options: .atomic)
    }

    private static func readStoredApiKey() -> String? {
        guard let data = try? Data(contentsOf: apiKeySidecarURL),
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { return nil }
        return key
    }
}
