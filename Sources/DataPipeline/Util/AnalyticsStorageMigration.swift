import CioInternalCommon
import Foundation

/// Analytics keeps storage per API key: identity in the `com.segment.storage.<key>` defaults and queued events
/// in a `segment/<key>/` folder that only that key's analytics instance uploads. When an app switches to a
/// public `pk_` key, this keeps the user's identity and their queued events.
///
/// Finished batches are moved to the new key's folder as they are, so they upload with the key written inside
/// them. An unfinished batch is never finished once its key is gone, so its complete events are moved to the new
/// key as a finished batch, written exactly as they were queued. Switching back to a legacy key does nothing.
struct AnalyticsStorageMigration {
    private static let suitePrefix = "com.segment.storage."
    // Identity analytics reads when it starts.
    private static let identityKeys = ["segment.userId", "segment.traits", "segment.anonymousId"]
    // Keys this SDK has run with, most recent last. Apps can also run Segment's own SDK, which uses the same
    // storage names, so only storage for these keys is ever moved.
    private static let usedKeysDefaultsKey = "io.customer.sdk.analyticsWriteKeys"
    // Analytics uploads every `.temp` file in its key's folder, and leaves others alone.
    private static let finishedBatchExtension = "temp"
    private static let unfinishedBatchSuffix = "-segment-events"
    private static let batchStart = #"{ "batch": ["#

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

    /// Copies the previous key's identity to `newKey`, keeping it for the previous key too, and never replacing
    /// identity `newKey` already has. Must run before analytics is created with `newKey`, as it reads identity then.
    /// Returns true when this launch switched to a public key, so queued events should be moved too.
    func copyIdentity(to newKey: String) -> Bool {
        let usedKeys = userDefaults.stringArray(forKey: Self.usedKeysDefaultsKey) ?? []
        defer { userDefaults.set(usedKeys.filter { $0 != newKey } + [newKey], forKey: Self.usedKeysDefaultsKey) }
        guard ApiKey.isPublic(newKey), let previousKey = usedKeys.last, previousKey != newKey else {
            return false
        }

        let newValues = userDefaults.persistentDomain(forName: Self.suitePrefix + newKey) ?? [:]
        let previousValues = userDefaults.persistentDomain(forName: Self.suitePrefix + previousKey) ?? [:]
        if !Self.identityKeys.contains(where: { newValues[$0] != nil }) {
            let identity = previousValues.filter { Self.identityKeys.contains($0.key) }
            userDefaults.setPersistentDomain(newValues.merging(identity) { current, _ in current }, forName: Self.suitePrefix + newKey)
            logger.info("Copied analytics identity to the new API key")
        }
        return true
    }

    /// Moves batches queued under earlier keys to `newKey` on `queue`, so main thread start up isn't slowed.
    /// Files are only ever added to the new key's folder whole, so analytics can run while this does.
    func moveQueuedEvents(to newKey: String, on queue: DispatchQueue = .global(qos: .utility)) {
        queue.async {
            let newDirectory = eventsDirectory.appendingPathComponent(newKey)
            let earlierKeys = (userDefaults.stringArray(forKey: Self.usedKeysDefaultsKey) ?? []).filter { $0 != newKey }
            for oldDirectory in earlierKeys.map(eventsDirectory.appendingPathComponent) {
                let files = (try? fileManager.contentsOfDirectory(at: oldDirectory, includingPropertiesForKeys: nil)) ?? []
                for file in files {
                    do {
                        try moveQueuedFile(file, from: oldDirectory.lastPathComponent, to: newKey, in: newDirectory)
                    } catch {
                        logger.error("Failed to move queued analytics events to the new API key", nil, error)
                    }
                }
            }
        }
    }

    /// Moves a finished batch as it is. Rewrites an unfinished one as a finished batch for `newKey` with its complete
    /// events, then deletes it. Files in any other format are kept.
    private func moveQueuedFile(_ file: URL, from oldKey: String, to newKey: String, in newDirectory: URL) throws {
        // Analytics names its own batches `<index>-segment-events`, so the old key in front keeps both
        // from taking the same name.
        let movedName = "\(oldKey)-\(file.deletingPathExtension().lastPathComponent).\(Self.finishedBatchExtension)"
        if file.pathExtension == Self.finishedBatchExtension {
            try fileManager.createDirectory(at: newDirectory, withIntermediateDirectories: true)
            try fileManager.moveItem(at: file, to: newDirectory.appendingPathComponent(movedName))
        } else if file.lastPathComponent.hasSuffix(Self.unfinishedBatchSuffix),
                  let events = try completeEvents(in: String(contentsOf: file, encoding: .utf8)) {
            if !events.isEmpty {
                let sentAt = Date().string(format: .iso8601WithMilliseconds)
                let batch = #"{"batch":[\#(events.joined(separator: ","))],"sentAt":"\#(sentAt)","writeKey":"\#(newKey)"}"#
                // Written next to the old batch first, so analytics never sees a part written file.
                let finishedFile = file.appendingPathExtension("finished")
                try batch.write(to: finishedFile, atomically: true, encoding: .utf8)
                try fileManager.createDirectory(at: newDirectory, withIntermediateDirectories: true)
                try fileManager.moveItem(at: finishedFile, to: newDirectory.appendingPathComponent(movedName))
            }
            try fileManager.removeItem(at: file)
        }
    }

    /// An unfinished batch is `{ "batch": [` then events split by commas, with no closing yet. Returns each complete
    /// event as written, dropping a last event cut off part way, or nil for any other format.
    private func completeEvents(in contents: String) -> [Substring]? {
        guard contents.hasPrefix(Self.batchStart) else {
            return nil
        }

        var events: [Substring] = []
        var depth = 0
        var inString = false
        var escaped = false
        var eventStart = contents.startIndex
        var index = contents.index(contents.startIndex, offsetBy: Self.batchStart.count)
        while index < contents.endIndex {
            let char = contents[index]
            if escaped {
                escaped = false
            } else if inString, char == "\\" {
                escaped = true
            } else if char == "\"" {
                inString.toggle()
            } else if !inString, char == "{" {
                if depth == 0 {
                    eventStart = index
                }
                depth += 1
            } else if !inString, char == "}" {
                depth -= 1
                if depth == 0 {
                    events.append(contents[eventStart ... index])
                }
            }
            index = contents.index(after: index)
        }
        return events
    }
}
