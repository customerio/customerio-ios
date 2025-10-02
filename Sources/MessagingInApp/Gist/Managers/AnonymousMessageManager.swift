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
            let currentMessageIds = Set(anonymousMessages.map(\.messageId))
            cleanupRemovedMessagesTracking(currentMessageIds: currentMessageIds)
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
        updateTracking(for: messageId) { tracking in
            tracking.timesShown += 1
            logger.logWithModuleTag("Anonymous message \(messageId) shown \(tracking.timesShown) time(s)", level: .debug)
        }
    }

    func markAnonymousAsDismissed(messageId: String) {
        updateTracking(for: messageId) { tracking in
            tracking.dismissed = true
            logger.logWithModuleTag("Anonymous message \(messageId) marked as dismissed", level: .debug)
        }
    }

    func clearAllAnonymousData() {
        logger.logWithModuleTag("Clearing all anonymous message data", level: .debug)

        // Clear message list, expiry, and tracking
        keyValueStorage.setString(nil, forKey: .broadcastMessages)
        keyValueStorage.setDouble(nil, forKey: .broadcastMessagesExpiry)
        keyValueStorage.setString(nil, forKey: .broadcastMessagesTracking)
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

    private func cleanupRemovedMessagesTracking(currentMessageIds: Set<String>) {
        var trackingData = getTrackingData()
        let trackedMessageIds = Set(trackingData.tracking.keys)
        let removedMessageIds = trackedMessageIds.subtracting(currentMessageIds)

        guard !removedMessageIds.isEmpty else { return }

        // Remove tracking for messages no longer in the current set
        removedMessageIds.forEach { trackingData.tracking.removeValue(forKey: $0) }
        setTrackingData(trackingData)

        logger.logWithModuleTag("Cleaned up tracking for \(removedMessageIds.count) removed messages", level: .debug)
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
