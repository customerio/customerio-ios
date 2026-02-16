import CioInternalCommon
import Foundation

// sourcery: InjectRegisterShared = "MessageInboxInstance"
// sourcery: InjectSingleton
class MessageInbox: MessageInboxInstance {
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

    init(logger: Logger, inAppMessageManager: InAppMessageManager) {
        self.logger = logger
        self.inAppMessageManager = inAppMessageManager

        // Subscribe to inbox messages state changes
        subscribeToInboxMessages()
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

    @MainActor
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
        // Clean up array on MainActor
        // nonisolated allows calling from deinit
        // Capture listenerId, not listener, to avoid retaining deallocating object
        let listenerId = ObjectIdentifier(listener)
        Task { @MainActor in
            listeners.removeAll { registration in
                guard let listener = registration.listener else { return true }
                return ObjectIdentifier(listener) == listenerId
            }
        }
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

    // MARK: - Private Helper Methods

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
    @MainActor
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
    @MainActor
    private func notifyListener(_ listener: InboxMessageChangeListener, messages: [InboxMessage]) {
        listener.onMessagesChanged(messages: messages)
    }
}
