import CioInternalCommon
import Foundation

// sourcery: InjectRegisterShared = "NotificationInbox"
// sourcery: InjectSingleton
// Thread safety: @MainActor isolation on mutable state. @unchecked Sendable for manual synchronization.
class DefaultNotificationInbox: NotificationInbox, @unchecked Sendable {
    private let logger: Logger
    private let inAppMessageManager: InAppMessageManager

    /// Storage for listener registrations
    @MainActor
    private var listeners: [ListenerRegistration] = []

    /// Subscriber for inbox messages state changes (kept alive to receive callbacks)
    private var storeSubscriber: InAppMessageStoreSubscriber?

    /// Subscription task for inbox messages state changes
    private var subscriptionTask: Task<Void, Never>?

    /// Registration wrapper for listener + topic filter
    private struct ListenerRegistration {
        weak var listener: NotificationInboxChangeListener?
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
        Task { @MainActor in
            subscribeToInboxMessages()
        }
    }

    deinit {
        subscriptionTask?.cancel()
        storeSubscriber = nil
    }

    // MARK: - NotificationInbox

    func getMessages(topic: String?) async -> [InboxMessage] {
        let state = await inAppMessageManager.state
        let messages = Array(state.inboxMessages)
        return filterMessagesByTopic(messages: messages, topic: topic)
    }

    @MainActor
    func addChangeListener(_ listener: NotificationInboxChangeListener, topic: String?) {
        // Add listener to array immediately to prevent remove-before-add race condition
        let registration = ListenerRegistration(listener: listener, topic: topic)
        listeners.append(registration)

        // Fetch current state and notify asynchronously
        Task { @MainActor [weak self, weak listener] in
            guard let self = self, let listener = listener else { return }

            let state = await inAppMessageManager.state
            let messages = Array(state.inboxMessages)
            let filteredMessages = self.filterMessagesByTopic(messages: messages, topic: topic)

            // Notify with the current state
            self.notifyListener(listener, messages: filteredMessages)
        }
    }

    func removeChangeListener(_ listener: NotificationInboxChangeListener) {
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

    func messages(topic: String?) -> AsyncStream<[InboxMessage]> {
        AsyncStream { continuation in
            // Yield current state immediately before setting up subscription
            Task { [weak self] in
                guard let self = self else {
                    continuation.finish()
                    return
                }

                let state = await inAppMessageManager.state
                let messages = Array(state.inboxMessages)
                let filteredMessages = self.filterMessagesByTopic(messages: messages, topic: topic)
                continuation.yield(filteredMessages)

                // Create subscriber for ongoing updates (store holds weak reference, must keep strong ref)
                let subscriber = InAppMessageStoreSubscriber { [weak self] state in
                    guard let self = self else {
                        continuation.finish()
                        return
                    }

                    let messages = Array(state.inboxMessages)
                    let filteredMessages = self.filterMessagesByTopic(messages: messages, topic: topic)
                    continuation.yield(filteredMessages)
                }

                // Subscribe to inbox messages changes
                let subscriptionTask = inAppMessageManager.subscribe(
                    keyPath: \.inboxMessages,
                    subscriber: subscriber
                )

                // Clean up on termination; capture subscriber to keep it alive
                continuation.onTermination = { @Sendable [subscriber] _ in
                    withExtendedLifetime(subscriber) {
                        subscriptionTask.cancel()
                    }
                }
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
    @MainActor
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

        // Notify each listener with filtered messages
        for registration in listeners {
            guard let listener = registration.listener else { continue }
            let filteredMessages = filterMessagesByTopic(messages: messages, topic: registration.topic)
            notifyListener(listener, messages: filteredMessages)
        }
    }

    /// Notify a single listener on main thread
    @MainActor
    private func notifyListener(_ listener: NotificationInboxChangeListener, messages: [InboxMessage]) {
        listener.onMessagesChanged(messages: messages)
    }
}
