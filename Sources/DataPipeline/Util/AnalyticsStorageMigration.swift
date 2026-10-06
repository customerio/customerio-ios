import CioInternalCommon
import Foundation

/// Analytics keys its storage by API key (`com.segment.storage.<key>` and `segment/<key>/`), so switching
/// keys would reset identity and drop queued events. When an app switches to a public `wk_` key, this moves
/// that storage over from the previously used key so the anonymous ID, user ID and queued events carry over.
struct AnalyticsStorageMigration {
    private static let suitePrefix = "com.segment.storage."
    private static let anonymousIdKey = "segment.anonymousId"
    // Key used by `DataPipeline` for calls made before the SDK is initialized.
    private static let deadInstanceKey = "DEADINSTANCE"
    // Last key the SDK ran with, so the next switch doesn't have to guess it.
    private static let lastKeyDefaultsKey = "io.customer.sdk.analyticsWriteKey"
    // Old key whose queued events still need moving to the new key.
    private static let pendingEventsDefaultsPrefix = "io.customer.sdk.analyticsPendingEventsFrom."

    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let eventsDirectory: URL
    private let logger: Logger

    init(
        logger: Logger,
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        eventsDirectory: URL = Self.defaultEventsDirectory
    ) {
        self.logger = logger
        self.fileManager = fileManager
        self.userDefaults = userDefaults
        self.eventsDirectory = eventsDirectory
    }

    /// Same base directory analytics uses for event files.
    static var defaultEventsDirectory: URL {
        #if (os(iOS) || os(watchOS)) && !targetEnvironment(macCatalyst)
        let searchPathDirectory = FileManager.SearchPathDirectory.documentDirectory
        #else
        let searchPathDirectory = FileManager.SearchPathDirectory.cachesDirectory
        #endif
        return FileManager.default.urls(for: searchPathDirectory, in: .userDomainMask)[0].appendingPathComponent("segment")
    }

    /// Must run before analytics is created with `newKey`. Does nothing for legacy keys, or if `newKey` already has identity.
    /// Queued events that fail to move are retried on the next launch.
    func migrate(to newKey: String) {
        defer { userDefaults.set(newKey, forKey: Self.lastKeyDefaultsKey) }
        guard ApiKey.isPublic(newKey) else {
            return
        }

        let pendingEventsKey = Self.pendingEventsDefaultsPrefix + newKey
        if !hasIdentity(newKey), let oldKey = previousKey(excluding: newKey) {
            userDefaults.set(oldKey, forKey: pendingEventsKey)
            moveUserDefaults(from: oldKey, to: newKey)
            logger.info("Moved analytics storage to the new API key")
        }
        if let oldKey = userDefaults.string(forKey: pendingEventsKey), moveEventFiles(from: oldKey, to: newKey) {
            userDefaults.removeObject(forKey: pendingEventsKey)
        }
    }

    private func hasIdentity(_ key: String) -> Bool {
        userDefaults.persistentDomain(forName: Self.suitePrefix + key)?[Self.anonymousIdKey] != nil
    }

    /// Last key the SDK ran with, or else the most recently used key that has identity stored.
    private func previousKey(excluding newKey: String) -> String? {
        if let lastKey = userDefaults.string(forKey: Self.lastKeyDefaultsKey), lastKey != newKey, hasIdentity(lastKey) {
            return lastKey
        }

        let directories = (try? fileManager.contentsOfDirectory(
            at: eventsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []

        return directories
            .map { (key: $0.lastPathComponent, modified: modificationDate($0)) }
            .filter { $0.key != newKey && $0.key != Self.deadInstanceKey && hasIdentity($0.key) }
            .max { $0.modified < $1.modified }?
            .key
    }

    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func moveUserDefaults(from oldKey: String, to newKey: String) {
        guard let values = userDefaults.persistentDomain(forName: Self.suitePrefix + oldKey) else {
            return
        }
        userDefaults.setPersistentDomain(values, forName: Self.suitePrefix + newKey)
        userDefaults.removePersistentDomain(forName: Self.suitePrefix + oldKey)
    }

    /// Returns false if any file couldn't be moved, so the move is retried later.
    private func moveEventFiles(from oldKey: String, to newKey: String) -> Bool {
        let oldDirectory = eventsDirectory.appendingPathComponent(oldKey)
        let newDirectory = eventsDirectory.appendingPathComponent(newKey)
        guard fileManager.fileExists(atPath: oldDirectory.path) else {
            return true
        }

        do {
            try fileManager.createDirectory(at: newDirectory, withIntermediateDirectories: true)
            for file in try fileManager.contentsOfDirectory(at: oldDirectory, includingPropertiesForKeys: nil) {
                try fileManager.moveItem(at: file, to: newDirectory.appendingPathComponent(file.lastPathComponent))
            }
            try fileManager.removeItem(at: oldDirectory)
            return true
        } catch {
            logger.error("Failed to move queued analytics events to the new API key, will retry on next launch", nil, error)
            return false
        }
    }
}
