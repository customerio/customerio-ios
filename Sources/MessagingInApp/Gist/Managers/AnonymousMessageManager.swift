import CioInternalCommon
import Foundation

/// Manages local storage and eligibility of anonymous (broadcast) in-app messages.
/// Anonymous messages are cached locally with a 60-minute expiry and filtered based on
/// frequency limits, delay periods, and dismiss status.
///
/// Storage keys use "broadcast_" prefix for backward compatibility with existing user data.
protocol AnonymousMessageManager: AutoMockable {
    /// Updates the local store of anonymous messages with a 60-minute expiry
    func updateAnonymousMessagesLocalStore(messages: [Message])

    /// Returns all eligible anonymous messages based on frequency, delay, and dismiss rules
    func getEligibleAnonymousMessages() -> [Message]

    /// Marks an anonymous message as seen (increments view counter)
    func markAnonymousAsSeen(messageId: String)

    /// Marks an anonymous message as dismissed
    func markAnonymousAsDismissed(messageId: String)

    /// Clears all anonymous message data from local storage
    func clearAllAnonymousData()
}

// sourcery: InjectRegisterShared = "AnonymousMessageManager"
// sourcery: InjectSingleton
class AnonymousMessageManagerImpl: AnonymousMessageManager {
    private let keyValueStorage: SharedKeyValueStorage
    private let dateUtil: DateUtil
    private let logger: Logger

    // Cache expiry duration: 60 minutes in milliseconds
    private let cacheExpiryDuration: TimeInterval = 60 * 60 * 1000

    init(
        keyValueStorage: SharedKeyValueStorage,
        dateUtil: DateUtil,
        logger: Logger
    ) {
        self.keyValueStorage = keyValueStorage
        self.dateUtil = dateUtil
        self.logger = logger
    }

    // MARK: - Public Methods

    func updateAnonymousMessagesLocalStore(messages: [Message]) {
        let anonymousMessages = messages.filter(\.isAnonymousMessage)

        if anonymousMessages.isEmpty {
            logger.logWithModuleTag("No anonymous messages in response, clearing local store", level: .debug)
            clearAllAnonymousData()
            return
        }

        logger.logWithModuleTag("Storing \(anonymousMessages.count) anonymous messages locally", level: .debug)

        // Store messages as JSON
        do {
            let messagesData = try serializeMessages(anonymousMessages)
            keyValueStorage.setString(messagesData, forKey: .broadcastMessages)

            // Set expiry timestamp (current time + 60 minutes)
            let expiryTime = dateUtil.now.timeIntervalSince1970 * 1000 + cacheExpiryDuration
            keyValueStorage.setDouble(expiryTime, forKey: .broadcastMessagesExpiry)

            // Clean up tracking data for messages no longer in the response
            cleanupRemovedMessagesTracking(currentMessages: anonymousMessages)
        } catch {
            logger.logWithModuleTag("Failed to serialize anonymous messages: \(error)", level: .error)
        }
    }

    func getEligibleAnonymousMessages() -> [Message] {
        // Check if cache has expired
        if isAnonymousMessagesExpired() {
            logger.logWithModuleTag("Anonymous messages cache expired", level: .debug)
            clearAllAnonymousData()
            return []
        }

        // Retrieve stored messages
        guard let messagesJson = keyValueStorage.string(.broadcastMessages) else {
            logger.logWithModuleTag("No anonymous messages in local store", level: .debug)
            return []
        }

        do {
            let storedMessages = try deserializeMessages(messagesJson)
            logger.logWithModuleTag("Retrieved \(storedMessages.count) anonymous messages from local store", level: .debug)

            // Filter based on eligibility rules
            let eligibleMessages = storedMessages.filter { message in
                isMessageEligible(message)
            }

            logger.logWithModuleTag("\(eligibleMessages.count) anonymous messages are eligible to display", level: .debug)
            return eligibleMessages
        } catch {
            logger.logWithModuleTag("Failed to deserialize anonymous messages: \(error)", level: .error)
            return []
        }
    }

    func markAnonymousAsSeen(messageId: String) {
        let currentCount = getAnonymousTimesShown(messageId: messageId)
        let newCount = currentCount + 1

        keyValueStorage.setInteger(newCount, forKey: timesShownKey(messageId: messageId))
        logger.logWithModuleTag("Anonymous message \(messageId) shown \(newCount) time(s)", level: .debug)
    }

    func markAnonymousAsDismissed(messageId: String) {
        keyValueStorage.setBool(true, forKey: dismissedKey(messageId: messageId))
        logger.logWithModuleTag("Anonymous message \(messageId) marked as dismissed", level: .debug)
    }

    func clearAllAnonymousData() {
        logger.logWithModuleTag("Clearing all anonymous message data", level: .debug)

        // Clear message list and expiry
        keyValueStorage.removeValue(forKey: .broadcastMessages)
        keyValueStorage.removeValue(forKey: .broadcastMessagesExpiry)

        // Note: Individual message tracking (times shown, dismissed, next show time) is intentionally kept
        // This is useful if the same message returns in the future
    }

    // MARK: - Private Helper Methods

    private func isAnonymousMessagesExpired() -> Bool {
        guard let expiryTime = keyValueStorage.double(.broadcastMessagesExpiry) else {
            return true // If no expiry time is set, consider it expired
        }

        let currentTime = dateUtil.now.timeIntervalSince1970 * 1000
        return currentTime >= expiryTime
    }

    private func isMessageEligible(_ message: Message) -> Bool {
        guard let broadcast = message.gistProperties.broadcast else {
            return false // Not an anonymous message
        }

        let messageId = message.messageId
        let frequency = broadcast.frequency

        // Check if message is in delay period
        if isAnonymousInDelayPeriod(messageId: messageId) {
            logger.logWithModuleTag("Anonymous message \(messageId) in delay period", level: .debug)
            return false
        }

        // Check dismiss status
        if isAnonymousDismissed(messageId: messageId), !frequency.ignoreDismiss {
            logger.logWithModuleTag("Anonymous message \(messageId) dismissed and ignoreDismiss=false", level: .debug)
            return false
        }

        // Check frequency limit
        let timesShown = getAnonymousTimesShown(messageId: messageId)
        if !frequency.isEmpty, timesShown >= frequency.count {
            logger.logWithModuleTag("Anonymous message \(messageId) reached frequency limit (\(frequency.count))", level: .debug)
            return false
        }

        return true
    }

    private func cleanupRemovedMessagesTracking(currentMessages: [Message]) {
        // Get all stored messages
        guard let messagesJson = keyValueStorage.string(.broadcastMessages),
              let storedMessages = try? deserializeMessages(messagesJson)
        else {
            return
        }

        let currentMessageIds = Set(currentMessages.map(\.messageId))
        let storedMessageIds = Set(storedMessages.map(\.messageId))

        // Find messages that were removed
        let removedMessageIds = storedMessageIds.subtracting(currentMessageIds)

        // Clear tracking for removed messages
        for messageId in removedMessageIds {
            clearAnonymousTracking(messageId: messageId)
        }

        if !removedMessageIds.isEmpty {
            logger.logWithModuleTag("Cleaned up tracking for \(removedMessageIds.count) removed messages", level: .debug)
        }
    }

    private func clearAnonymousTracking(messageId: String) {
        keyValueStorage.removeValue(forKey: timesShownKey(messageId: messageId))
        keyValueStorage.removeValue(forKey: dismissedKey(messageId: messageId))
        keyValueStorage.removeValue(forKey: nextShowTimeKey(messageId: messageId))
    }

    // MARK: - Storage Access Helpers

    private func getAnonymousTimesShown(messageId: String) -> Int {
        keyValueStorage.integer(timesShownKey(messageId: messageId)) ?? 0
    }

    private func isAnonymousDismissed(messageId: String) -> Bool {
        keyValueStorage.bool(dismissedKey(messageId: messageId)) ?? false
    }

    private func isAnonymousInDelayPeriod(messageId: String) -> Bool {
        guard let nextShowTime = keyValueStorage.double(nextShowTimeKey(messageId: messageId)) else {
            return false
        }

        let currentTime = dateUtil.now.timeIntervalSince1970 * 1000
        return currentTime < nextShowTime
    }

    func setAnonymousNextShowTime(messageId: String, delay: Int) {
        let currentTime = dateUtil.now.timeIntervalSince1970 * 1000
        let nextShowTime = currentTime + Double(delay * 1000) // Convert seconds to milliseconds

        keyValueStorage.setDouble(nextShowTime, forKey: nextShowTimeKey(messageId: messageId))
        logger.logWithModuleTag("Anonymous message \(messageId) next show time set to \(nextShowTime)", level: .debug)
    }

    // MARK: - Storage Key Helpers

    private func timesShownKey(messageId: String) -> KeyValueStorageKey {
        // Using custom string keys for per-message tracking since enum can't be dynamic
        KeyValueStorageKey(rawValue: "broadcast_times_shown_\(messageId)") ?? .broadcastMessages
    }

    private func dismissedKey(messageId: String) -> KeyValueStorageKey {
        KeyValueStorageKey(rawValue: "broadcast_dismissed_\(messageId)") ?? .broadcastMessages
    }

    private func nextShowTimeKey(messageId: String) -> KeyValueStorageKey {
        KeyValueStorageKey(rawValue: "broadcast_next_show_time_\(messageId)") ?? .broadcastMessages
    }

    // MARK: - Serialization

    private func serializeMessages(_ messages: [Message]) throws -> String {
        // Convert messages to dictionary format for JSON serialization
        let messagesData = messages.map { message -> [String: Any] in
            [
                "messageId": message.messageId,
                "queueId": message.queueId as Any,
                "priority": message.priority as Any,
                "properties": message.properties
            ]
        }

        let jsonData = try JSONSerialization.data(withJSONObject: messagesData, options: [])
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw NSError(domain: "AnonymousMessageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert JSON data to string"])
        }

        return jsonString
    }

    private func deserializeMessages(_ jsonString: String) throws -> [Message] {
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw NSError(domain: "AnonymousMessageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert string to JSON data"])
        }

        guard let messagesArray = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String: Any]] else {
            throw NSError(domain: "AnonymousMessageManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format"])
        }

        return messagesArray.compactMap { dict -> Message? in
            guard let messageId = dict["messageId"] as? String else {
                return nil
            }

            let queueId = dict["queueId"] as? String
            let priority = dict["priority"] as? Int
            let properties = dict["properties"] as? [String: Any]

            return Message(
                messageId: messageId,
                queueId: queueId,
                priority: priority,
                properties: properties
            )
        }
    }
}

// MARK: - Extension for tracking after display

extension AnonymousMessageManagerImpl {
    /// Called after an anonymous message is displayed to update delay period
    func onAnonymousMessageDisplayed(message: Message) {
        guard let broadcast = message.gistProperties.broadcast else {
            return
        }

        let delay = broadcast.frequency.delay
        if delay > 0 {
            setAnonymousNextShowTime(messageId: message.messageId, delay: delay)
        }
    }
}
