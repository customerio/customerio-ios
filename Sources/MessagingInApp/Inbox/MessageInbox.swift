import CioInternalCommon
import Foundation

// sourcery: InjectRegisterShared = "MessageInboxInstance"
// sourcery: InjectSingleton
@MainActor
final class MessageInbox: MessageInboxInstance {
    private let logger: Logger
    private let inAppMessageManager: InAppMessageManager

    /// Storage for listener registrations
    private var listeners: [ListenerRegistration] = []

    /// Subscriber for inbox messages state changes (kept alive to receive callbacks)
    private var storeSubscriber: InAppMessageStoreSubscriber?

    /// Subscription task for inbox messages state changes
    private var subscriptionTask: Task<Void, Never>?

    /// Registration wrapper for listener + topic filter
    private struct ListenerRegistration {
        weak var listener: InboxMessageChangeListener?
        let topic: String?

        /// Remove registrations with nil listeners
        var isValid: Bool {
            listener != nil
        }
    }

    nonisolated init(logger: Logger, inAppMessageManager: InAppMessageManager) {
        self.logger = logger
        self.inAppMessageManager = inAppMessageManager

        // Subscribe to inbox messages state changes on MainActor
        Task { @MainActor [weak self] in
            self?.subscribeToInboxMessages()
        }
    }

    deinit {
        subscriptionTask?.cancel()
        storeSubscriber = nil
    }

    // MARK: - MessageInboxInstance

    func getMessages(topic: String?) async -> [InboxMessage] {
        let state = await inAppMessageManager.state
        let messages = Array(state.inboxMessages)
        return filterMessagesByTopic(messages: messages, topic: topic)
    }

    func addChangeListener(_ listener: InboxMessageChangeListener, topic: String?) {
        let registration = ListenerRegistration(listener: listener, topic: topic)
        listeners.append(registration)

        // Notify listener immediately with current state
        // Capture listener weakly to avoid retaining it if it's removed before callback completes
        Task { @MainActor [weak listener] in
            guard let listener = listener else { return }

            let state = await inAppMessageManager.state
            let messages = Array(state.inboxMessages)
            let filteredMessages = filterMessagesByTopic(messages: messages, topic: topic)
            notifyListener(listener, messages: filteredMessages)
        }
    }

    func removeChangeListener(_ listener: InboxMessageChangeListener) {
        let listenerId = ObjectIdentifier(listener)
        listeners.removeAll { registration in
            guard let existing = registration.listener else { return true }
            return ObjectIdentifier(existing) == listenerId
        }
    }

    nonisolated func markMessageOpened(message: InboxMessage) {
        Task { @MainActor [weak self] in
            self?.dispatchInboxAction(.updateOpened(message: message, opened: true))
        }
    }

    nonisolated func markMessageUnopened(message: InboxMessage) {
        Task { @MainActor [weak self] in
            self?.dispatchInboxAction(.updateOpened(message: message, opened: false))
        }
    }

    nonisolated func markMessageDeleted(message: InboxMessage) {
        Task { @MainActor [weak self] in
            self?.dispatchInboxAction(.deleteMessage(message: message))
        }
    }

    nonisolated func trackMessageClicked(message: InboxMessage, actionName: String?) {
        Task { @MainActor [weak self] in
            self?.dispatchInboxAction(.trackClicked(message: message, actionName: actionName))
        }
    }

    // MARK: - Private Helper Methods

    /// Dispatches an inbox action to the message manager.
    private func dispatchInboxAction(_ action: InAppMessageAction.InboxAction) {
        inAppMessageManager.dispatch(action: .inboxAction(action: action))
    }

    /// Filters messages by topic (case-insensitive) if specified, otherwise returns all messages.
    /// Always sorts results by sentAt newest first.
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

    /// Subscribe to inbox messages state changes
    private func subscribeToInboxMessages() {
        let subscriber = InAppMessageStoreSubscriber { [weak self] state in
            guard let self = self else { return }

            let messages = Array(state.inboxMessages)
            // Ensure all listener access happens on MainActor
            Task { @MainActor in
                self.notifyAllListeners(messages: messages)
            }
        }

        // Keep strong reference to subscriber so store's weak reference remains valid
        storeSubscriber = subscriber

        // Subscribe to inbox messages - Array equality detects all property changes
        subscriptionTask = inAppMessageManager.subscribe(
            keyPath: \.inboxMessages,
            subscriber: subscriber
        )
    }

    /// Notify all registered listeners with filtered messages
    private func notifyAllListeners(messages: [InboxMessage]) {
        // Clean up nil listeners and get valid registrations only
        listeners.removeAll { !$0.isValid }

        // Prepare notifications and notify each listener
        let notificationsToSend: [(InboxMessageChangeListener, [InboxMessage])] = listeners.compactMap { registration in
            guard let listener = registration.listener else { return nil }
            let filteredMessages = filterMessagesByTopic(messages: messages, topic: registration.topic)
            return (listener, filteredMessages)
        }

        // Notify all listeners (already on main thread)
        for (listener, filteredMessages) in notificationsToSend {
            notifyListener(listener, messages: filteredMessages)
        }
    }

    /// Notify a single listener on main thread
    private func notifyListener(_ listener: InboxMessageChangeListener, messages: [InboxMessage]) {
        listener.onMessagesChanged(messages: messages)
    }
}
