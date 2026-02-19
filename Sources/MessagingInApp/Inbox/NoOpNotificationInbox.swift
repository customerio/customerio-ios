import CioInternalCommon
import Foundation

/// No-op implementation of NotificationInbox used when the MessagingInApp module is not initialized.
/// All methods are no-ops that safely do nothing, allowing graceful degradation.
class NoOpNotificationInbox: NotificationInbox {
    private let logger: Logger

    init() {
        self.logger = DIGraphShared.shared.logger
        logger.info("MessagingInApp module not initialized. Call MessagingInApp.initialize() to use inbox features.")
    }

    func getMessages(topic: String?) async -> [InboxMessage] {
        []
    }

    @MainActor
    func addChangeListener(_ listener: NotificationInboxChangeListener, topic: String?) {
        // No-op
    }

    func removeChangeListener(_ listener: NotificationInboxChangeListener) {
        // No-op
    }

    func markMessageOpened(message: InboxMessage) {
        // No-op
    }

    func markMessageUnopened(message: InboxMessage) {
        // No-op
    }

    func markMessageDeleted(message: InboxMessage) {
        // No-op
    }

    func trackMessageClicked(message: InboxMessage, actionName: String?) {
        // No-op
    }
}
