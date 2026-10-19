import CioInternalCommon
import Foundation

/// Analytics keys its storage by API key (`com.segment.storage.<key>` and `segment/<key>/`), so switching
/// keys would reset identity and drop queued events. When an app switches to a public `pk_` key, this moves
/// that storage over from the previously used key so the anonymous ID, user ID and queued events carry over.
/// Finished batches are rewritten to the new key, since the new key's source is where they now belong and the
/// old key may be disabled before they upload. Switching back to a legacy key does not reverse the move.
struct AnalyticsStorageMigration {
    private static let suitePrefix = "com.segment.storage."
    private static let anonymousIdKey = "segment.anonymousId"
    // Key used by `DataPipeline` for calls made before the SDK is initialized.
    private static let deadInstanceKey = "DEADINSTANCE"
    // Last key the SDK ran with, so the next switch doesn't have to guess it.
    private static let lastKeyDefaultsKey = "io.customer.sdk.analyticsWriteKey"
    // Old keys whose queued events still need moving to the new key.
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
            // Carry over keys whose events an earlier switch to `oldKey` didn't finish moving.
            let olderPendingEventsKey = Self.pendingEventsDefaultsPrefix + oldKey
            let sourceKeys = (userDefaults.stringArray(forKey: olderPendingEventsKey) ?? []) + [oldKey]
            userDefaults.set(sourceKeys, forKey: pendingEventsKey)
            userDefaults.removeObject(forKey: olderPendingEventsKey)
            moveUserDefaults(from: oldKey, to: newKey)
            logger.info("Moved analytics storage to the new API key")
        }
        guard let sourceKeys = userDefaults.stringArray(forKey: pendingEventsKey) else {
            return
        }
        let unmovedKeys = sourceKeys.filter { !moveEventFiles(from: $0, to: newKey) }
        if unmovedKeys.isEmpty {
            userDefaults.removeObject(forKey: pendingEventsKey)
        } else {
            userDefaults.set(unmovedKeys, forKey: pendingEventsKey)
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
            var allMoved = true
            for file in try fileManager.contentsOfDirectory(at: oldDirectory, includingPropertiesForKeys: nil) {
                do {
                    try rewriteBatchKey(in: file, from: oldKey, to: newKey)
                    try fileManager.moveItem(at: file, to: destination(for: file, in: newDirectory))
                } catch {
                    // Leave this file behind and keep moving the rest.
                    logger.error("Failed to move a queued analytics batch to the new API key, will retry on next launch", nil, error)
                    allMoved = false
                }
            }
            guard allMoved else {
                return false
            }
            try fileManager.removeItem(at: oldDirectory)
            return true
        } catch {
            logger.error("Failed to move queued analytics events to the new API key, will retry on next launch", nil, error)
            return false
        }
    }

    /// Batches from different keys share index-based names, so a taken name gets a unique prefix.
    /// Analytics uploads every `.temp` file in the folder, whatever its name.
    private func destination(for file: URL, in directory: URL) -> URL {
        let destination = directory.appendingPathComponent(file.lastPathComponent)
        guard fileManager.fileExists(atPath: destination.path) else {
            return destination
        }
        return directory.appendingPathComponent("\(UUID().uuidString)-\(file.lastPathComponent)")
    }

    /// Finished batches (`.temp` files) end with `"writeKey":"<key>"}`, which the upload uses. Only that
    /// trailing field changes, so event properties are left as queued. Unfinished ones get the new key when
    /// analytics finishes them. Throws if a finished batch can't be rewritten, so it isn't moved with the old key.
    private func rewriteBatchKey(in file: URL, from oldKey: String, to newKey: String) throws {
        guard file.pathExtension == "temp" else {
            return
        }
        let contents = try String(contentsOf: file, encoding: .utf8)
        // Rewritten by an earlier try whose move then failed.
        if trailingKeyRange(of: newKey, in: contents) != nil {
            return
        }
        guard let range = trailingKeyRange(of: oldKey, in: contents) else {
            throw BatchKeyNotFoundError()
        }
        try contents.replacingCharacters(in: range, with: #""writeKey":"\#(newKey)"}"#)
            .write(to: file, atomically: true, encoding: .utf8)
    }

    private func trailingKeyRange(of key: String, in contents: String) -> Range<String.Index>? {
        guard let range = contents.range(of: #""writeKey":"\#(key)"}"#, options: .backwards),
              contents[range.upperBound...].allSatisfy(\.isWhitespace)
        else {
            return nil
        }
        return range
    }
}

/// A finished analytics batch didn't end with the expected `writeKey` field.
struct BatchKeyNotFoundError: Error {}
