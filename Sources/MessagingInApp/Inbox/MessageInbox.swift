import CioInternalCommon
import Foundation

// sourcery: InjectRegisterShared = "MessageInbox"
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

    func getMessages() async -> [InboxMessage] {
        logger.logWithModuleTag("getMessages() called - returning empty array (not yet implemented)", level: .debug)
        return []
    }

    func addChangeListener(_ listener: InboxMessageChangeListener) {
        logger.logWithModuleTag("addChangeListener() called (not yet implemented)", level: .debug)
    }

    func removeChangeListener(_ listener: InboxMessageChangeListener) {
        logger.logWithModuleTag("removeChangeListener() called (not yet implemented)", level: .debug)
    }

    func markMessageOpened(message: InboxMessage) {
        logger.logWithModuleTag("markMessageOpened(message: \(message.describeForLogs)) called (not yet implemented)", level: .debug)
    }

    func markMessageUnopened(message: InboxMessage) {
        logger.logWithModuleTag("markMessageUnopened(message: \(message.describeForLogs)) called (not yet implemented)", level: .debug)
    }

    func markMessageDeleted(message: InboxMessage) {
        logger.logWithModuleTag("markMessageDeleted(message: \(message.describeForLogs)) called (not yet implemented)", level: .debug)
    }

    func trackMessageClicked(message: InboxMessage, actionName: String?) {
        let actionInfo = actionName.map { "actionName: \($0)" } ?? "no actionName"
        logger.logWithModuleTag("trackMessageClicked(message: \(message.describeForLogs), \(actionInfo)) called (not yet implemented)", level: .debug)
    }
}
