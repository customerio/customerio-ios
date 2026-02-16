import CioInternalCommon
import Foundation

// sourcery: InjectRegisterShared = "MessageInboxInstance"
// sourcery: InjectSingleton
class MessageInbox: MessageInboxInstance {
    private let logger: Logger
    private let inAppMessageManager: InAppMessageManager

    init(logger: Logger, inAppMessageManager: InAppMessageManager) {
        self.logger = logger
        self.inAppMessageManager = inAppMessageManager

        logger.logWithModuleTag("MessageInbox initialized", level: .debug)
    }

    // MARK: - MessageInboxInstance

    func getMessages(topic: String?) async -> [InboxMessage] {
        let state = await inAppMessageManager.state
        let messages = Array(state.inboxMessages)
        return filterMessagesByTopic(messages: messages, topic: topic)
    }

    /// Filters messages by topic if specified and sorts by sentAt (newest first).
    /// Topic matching is case-insensitive.
    ///
    /// - Parameters:
    ///   - messages: The messages to filter
    ///   - topic: The topic filter, or nil to return all messages
    /// - Returns: Filtered and sorted list of messages
    private func filterMessagesByTopic(messages: [InboxMessage], topic: String?) -> [InboxMessage] {
        let filteredMessages: [InboxMessage]
        if let topic = topic {
            filteredMessages = messages.filter { message in
                message.topics.contains { $0.compare(topic, options: .caseInsensitive) == .orderedSame }
            }
        } else {
            filteredMessages = messages
        }
        return filteredMessages.sorted { $0.sentAt > $1.sentAt }
    }

    func addChangeListener(_ listener: InboxMessageChangeListener) {
        logger.logWithModuleTag("addChangeListener() called (not yet implemented)", level: .debug)
    }

    func removeChangeListener(_ listener: InboxMessageChangeListener) {
        logger.logWithModuleTag("removeChangeListener() called (not yet implemented)", level: .debug)
    }

    func markMessageOpened(message: InboxMessage) {
        inAppMessageManager.dispatch(action: .inboxAction(action: .updateOpened(message: message, opened: true)))
    }

    func markMessageUnopened(message: InboxMessage) {
        inAppMessageManager.dispatch(action: .inboxAction(action: .updateOpened(message: message, opened: false)))
    }

    func markMessageDeleted(message: InboxMessage) {
        inAppMessageManager.dispatch(action: .inboxAction(action: .deleteMessage(message: message)))
    }

    func trackMessageClicked(message: InboxMessage, actionName: String?) {
        inAppMessageManager.dispatch(action: .inboxAction(action: .trackClicked(message: message, actionName: actionName)))
    }
}
