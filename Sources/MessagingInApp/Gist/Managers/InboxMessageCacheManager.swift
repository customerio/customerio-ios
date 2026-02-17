import CioInternalCommon
import Foundation

// sourcery: InjectRegisterShared = "InboxMessageCacheManager"
// sourcery: InjectSingleton
class InboxMessageCacheManager {
    private let keyValueStore: SharedKeyValueStorage
    private let logger: Logger
    private let lock = NSLock()

    init(keyValueStore: SharedKeyValueStorage, logger: Logger) {
        self.keyValueStore = keyValueStore
        self.logger = logger
    }

    /// Retrieves the cached opened status for a specific inbox message.
    /// - Parameter queueId: The unique identifier for the inbox message
    /// - Returns: The cached opened status, or nil if not cached
    func getOpenedStatus(queueId: String) -> Bool? {
        lock.lock()
        defer { lock.unlock() }

        return getAllOpenedStatuses()[queueId]
    }

    /// Saves the opened status for a specific inbox message.
    /// - Parameters:
    ///   - queueId: The unique identifier for the inbox message
    ///   - opened: The opened status to cache
    func saveOpenedStatus(queueId: String, opened: Bool) {
        lock.lock()
        defer { lock.unlock() }

        var statusDict = getAllOpenedStatuses()
        statusDict[queueId] = opened
        setAllOpenedStatuses(statusDict)
    }

    /// Clears the cached opened status for a specific inbox message.
    /// - Parameter queueId: The unique identifier for the inbox message
    func clearOpenedStatus(queueId: String) {
        lock.lock()
        defer { lock.unlock() }

        var statusDict = getAllOpenedStatuses()
        statusDict.removeValue(forKey: queueId)
        setAllOpenedStatuses(statusDict)
    }

    /// Clears all cached opened statuses.
    /// Called when user logs out or state is reset.
    func clearAll() {
        lock.lock()
        defer { lock.unlock() }

        keyValueStore.setData(nil, forKey: .inboxMessagesOpenedStatus)
    }

    // MARK: - Private Methods

    private func getAllOpenedStatuses() -> [String: Bool] {
        guard let data = keyValueStore.data(.inboxMessagesOpenedStatus),
              let statusDict = try? JSONDecoder().decode([String: Bool].self, from: data)
        else {
            return [:]
        }
        return statusDict
    }

    private func setAllOpenedStatuses(_ statusDict: [String: Bool]) {
        guard let data = try? JSONEncoder().encode(statusDict) else {
            logger.logWithModuleTag("Failed to encode inbox opened status", level: .error)
            return
        }
        keyValueStore.setData(data, forKey: .inboxMessagesOpenedStatus)
    }
}
