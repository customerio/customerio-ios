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
            logger.logWithModuleTag("No anonymous messages in server response - clearing local storage as anonymous messages have expired", level: .debug)
            clearAllAnonymousData()
            return
        }

        // Get previous messages for cleanup comparison
        let previousMessages = (try? getStoredMessages()) ?? []

        // Store messages as JSON
        do {
            let messagesData = try serializeMessages(anonymousMessages)
            keyValueStorage.setString(messagesData, forKey: .broadcastMessages)

            // Set expiry timestamp (current time + 60 minutes)
            let expiryTime = dateUtil.now.timeIntervalSince1970 * 1000 + cacheExpiryDuration
            keyValueStorage.setDouble(expiryTime, forKey: .broadcastMessagesExpiry)

            logger.logWithModuleTag("Saved \(anonymousMessages.count) anonymous messages to local store", level: .debug)

            // Clean up tracking data for messages no longer in the response
            cleanupExpiredAnonymousTracking(currentMessages: anonymousMessages, previousMessages: previousMessages)
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
        guard let storedMessages = try? getStoredMessages() else {
            logger.logWithModuleTag("No anonymous messages in local store", level: .debug)
            return []
        }

        logger.logWithModuleTag("Retrieved \(storedMessages.count) anonymous messages from local store", level: .debug)

        // Filter based on eligibility rules
        let eligibleMessages = storedMessages.filter { message in
            isMessageEligible(message)
        }

        logger.logWithModuleTag("\(eligibleMessages.count) anonymous messages are eligible to display", level: .debug)
        return eligibleMessages
    }

    func markAnonymousAsSeen(messageId: String) {
        logger.logWithModuleTag("Marking anonymous message \(messageId) as seen", level: .debug)

        // Get frequency details from stored message JSON
        guard let frequency = getAnonymousFrequency(messageId: messageId) else {
            logger.logWithModuleTag("Could not find anonymous message details for \(messageId)", level: .debug)
            return
        }

        // Increment times shown counter
        var trackingData = getTrackingData()
        var messageTracking = trackingData.tracking[messageId] ?? MessageTracking()
        messageTracking.timesShown += 1
        trackingData.tracking[messageId] = messageTracking
        setTrackingData(trackingData)

        let numberOfTimesShown = messageTracking.timesShown

        // Apply frequency rules
        if frequency.count == 1 {
            // Mark as permanently dismissed for count=1
            var updatedTracking = getTrackingData()
            var updatedMessageTracking = updatedTracking.tracking[messageId] ?? MessageTracking()
            updatedMessageTracking.dismissed = true
            updatedTracking.tracking[messageId] = updatedMessageTracking
            setTrackingData(updatedTracking)
            logger.logWithModuleTag("Marked anonymous message \(messageId) as permanently dismissed (count=1)", level: .debug)
        } else if frequency.delay > 0 {
            // Set next show time based on delay
            let currentTime = dateUtil.now.timeIntervalSince1970 * 1000
            let nextShowTimeMillis = currentTime + Double(frequency.delay * 1000)
            var updatedTracking = getTrackingData()
            var updatedMessageTracking = updatedTracking.tracking[messageId] ?? MessageTracking()
            updatedMessageTracking.nextShowTime = nextShowTimeMillis
            updatedTracking.tracking[messageId] = updatedMessageTracking
            setTrackingData(updatedTracking)

            let nextShowDate = Date(timeIntervalSince1970: nextShowTimeMillis / 1000)
            logger.logWithModuleTag("Marked anonymous message \(messageId) as seen, shown \(numberOfTimesShown) times, next show time: \(nextShowDate)", level: .debug)
        } else {
            logger.logWithModuleTag("Marked anonymous message \(messageId) as seen, shown \(numberOfTimesShown) times, no delay restriction", level: .debug)
        }
    }

    func markAnonymousAsDismissed(messageId: String) {
        logger.logWithModuleTag("Marking anonymous message \(messageId) as dismissed", level: .debug)

        // Get frequency details from stored message JSON
        guard let frequency = getAnonymousFrequency(messageId: messageId) else {
            logger.logWithModuleTag("Could not find anonymous message details for \(messageId)", level: .debug)
            return
        }

        // Check ignoreDismiss flag from message
        if frequency.ignoreDismiss {
            logger.logWithModuleTag("Anonymous message \(messageId) is set to ignore dismiss", level: .debug)
            return
        }

        // Mark as dismissed
        var trackingData = getTrackingData()
        var messageTracking = trackingData.tracking[messageId] ?? MessageTracking()
        messageTracking.dismissed = true
        trackingData.tracking[messageId] = messageTracking
        setTrackingData(trackingData)
        logger.logWithModuleTag("Marked anonymous message \(messageId) as dismissed and will not show again", level: .debug)
    }

    func clearAllAnonymousData() {
        logger.logWithModuleTag("Cleared all anonymous message storage", level: .debug)

        // Clear message list and expiry only - tracking data is intentionally kept
        keyValueStorage.setString(nil, forKey: .broadcastMessages)
        keyValueStorage.setDouble(nil, forKey: .broadcastMessagesExpiry)

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

        // Check dismiss status (matches Android order)
        if isAnonymousDismissed(messageId: messageId), !frequency.ignoreDismiss {
            logger.logWithModuleTag("Anonymous message \(messageId) dismissed and ignoreDismiss=false", level: .debug)
            return false
        }

        // Check if message is in delay period
        if isAnonymousInDelayPeriod(messageId: messageId) {
            logger.logWithModuleTag("Anonymous message \(messageId) in delay period", level: .debug)
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

    // MARK: - Storage Access Helpers

    private func getTrackingData() -> MessagesTrackingData {
        guard let jsonString = keyValueStorage.string(.broadcastMessagesTracking),
              let jsonData = jsonString.data(using: .utf8),
              let trackingData = try? JSONDecoder().decode(MessagesTrackingData.self, from: jsonData)
        else {
            return MessagesTrackingData()
        }
        return trackingData
    }

    private func setTrackingData(_ data: MessagesTrackingData) {
        guard let jsonData = try? JSONEncoder().encode(data),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            logger.logWithModuleTag("Failed to encode tracking data", level: .error)
            return
        }
        keyValueStorage.setString(jsonString, forKey: .broadcastMessagesTracking)
    }

    private func updateTracking(for messageId: String, update: (inout MessageTracking) -> Void) {
        var trackingData = getTrackingData()
        var messageTracking = trackingData.tracking[messageId] ?? MessageTracking()
        update(&messageTracking)
        trackingData.tracking[messageId] = messageTracking
        setTrackingData(trackingData)
    }

    private func getAnonymousTimesShown(messageId: String) -> Int {
        getTrackingData().tracking[messageId]?.timesShown ?? 0
    }

    private func isAnonymousDismissed(messageId: String) -> Bool {
        getTrackingData().tracking[messageId]?.dismissed ?? false
    }

    private func isAnonymousInDelayPeriod(messageId: String) -> Bool {
        guard let nextShowTime = getTrackingData().tracking[messageId]?.nextShowTime else {
            return false
        }
        let currentTime = dateUtil.now.timeIntervalSince1970 * 1000
        return currentTime < nextShowTime
    }

    func setAnonymousNextShowTime(messageId: String, delay: Int) {
        let currentTime = dateUtil.now.timeIntervalSince1970 * 1000
        let nextShowTime = currentTime + Double(delay * 1000)

        updateTracking(for: messageId) { tracking in
            tracking.nextShowTime = nextShowTime
        }

        logger.logWithModuleTag("Anonymous message \(messageId) next show time set to \(nextShowTime)", level: .debug)
    }

    private func getAnonymousFrequency(messageId: String) -> BroadcastFrequency? {
        guard let storedMessages = try? getStoredMessages() else {
            return nil
        }
        let message = storedMessages.first { $0.messageId == messageId }
        return message?.gistProperties.broadcast?.frequency
    }

    private func getStoredMessages() throws -> [Message] {
        guard let jsonString = keyValueStorage.string(.broadcastMessages) else {
            return []
        }
        return try deserializeMessages(jsonString)
    }

    private func cleanupExpiredAnonymousTracking(currentMessages: [Message], previousMessages: [Message]) {
        let currentMessageIds = Set(currentMessages.map(\.messageId))
        let previousMessageIds = Set(previousMessages.map(\.messageId))
        let expiredMessageIds = previousMessageIds.subtracting(currentMessageIds)

        guard !expiredMessageIds.isEmpty else { return }

        var trackingData = getTrackingData()
        expiredMessageIds.forEach { trackingData.tracking.removeValue(forKey: $0) }
        setTrackingData(trackingData)

        logger.logWithModuleTag("Cleaned up tracking for \(expiredMessageIds.count) expired messages", level: .debug)
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
