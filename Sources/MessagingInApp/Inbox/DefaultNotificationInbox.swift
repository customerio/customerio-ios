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

    /// Host listener notified of inbox message actions (item 13). Guarded by `inboxEventListenerLock`
    /// because it is set/read from arbitrary threads (the public setter vs. the action callback).
    private var inboxEventListener: InboxEventListener?
    private let inboxEventListenerLock = NSLock()

    /// Message ids already reported to the host via `inboxMessageShown`, so "shown" fires at most once
    /// per message per app session even though the UI may call `notifyMessageShown` on every render.
    /// Guarded by `shownMessageIdsLock` because `notifyMessageShown` can be called off the main thread.
    private var shownMessageIds: Set<String> = []
    private let shownMessageIdsLock = NSLock()

    /// Ids already reported "opened" so the host `inboxMessageOpened` callback fires at most once per
    /// message per session (mirrors `shownMessageIds`). Guarded by `openedMessageIdsLock`.
    private var openedMessageIds: Set<String> = []
    private let openedMessageIdsLock = NSLock()

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
        // Observe-only host callback: a message was opened. Dedupe per session (mirrors
        // notifyMessageShown) so repeated marks — incl. via the public API — fire it at most once.
        openedMessageIdsLock.lock()
        let alreadyOpened = openedMessageIds.contains(message.queueId)
        if !alreadyOpened { openedMessageIds.insert(message.queueId) }
        openedMessageIdsLock.unlock()
        guard !alreadyOpened else { return }
        // Reflect the just-applied opened state: the resolved `message` predates the dispatch above.
        let listener = currentInboxEventListener()
        deliverOnMain { listener?.inboxMessageOpened(message: message.copy(opened: true)) }
    }

    func markMessageUnopened(message: InboxMessage) {
        inAppMessageManager.dispatch(action: .inboxAction(action: .updateOpened(message: message, opened: false)))
    }

    func markMessageDeleted(message: InboxMessage) {
        inAppMessageManager.dispatch(action: .inboxAction(action: .deleteMessage(message: message)))
        // Observe-only host callback: a message was dismissed/removed.
        let listener = currentInboxEventListener()
        deliverOnMain { listener?.inboxMessageDismissed(message: message) }
    }

    func trackMessageClicked(message: InboxMessage, actionName: String?) {
        inAppMessageManager.dispatch(action: .inboxAction(action: .trackClicked(message: message, actionName: actionName)))
    }

    func setInboxEventListener(_ listener: InboxEventListener?) {
        inboxEventListenerLock.lock()
        inboxEventListener = listener
        inboxEventListenerLock.unlock()
    }

    func notifyMessageActionTaken(message: InboxMessage, actionValue: String, actionName: String) -> Bool {
        guard let listener = currentInboxEventListener() else { return false }
        return listener.inboxMessageActionTaken(message: message, actionValue: actionValue, actionName: actionName)
    }

    func notifyMessageShown(message: InboxMessage) {
        // Dedupe: only fire "shown" the first time we see this message id this session.
        shownMessageIdsLock.lock()
        let alreadyShown = shownMessageIds.contains(message.queueId)
        if !alreadyShown { shownMessageIds.insert(message.queueId) }
        shownMessageIdsLock.unlock()
        guard !alreadyShown else { return }
        let listener = currentInboxEventListener()
        deliverOnMain { listener?.inboxMessageShown(message: message) }
    }

    /// Delivers a host `InboxEventListener` callback on the main thread. Inbox mutations can be
    /// triggered from background queues (the data layer / SwiftUI Tasks), but host UI code expects
    /// its callbacks on main. Runs inline when already on main (so callers/tests observe it
    /// synchronously), otherwise hops to the main queue.
    private func deliverOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    /// Thread-safe read of the host listener (set/read from arbitrary threads).
    private func currentInboxEventListener() -> InboxEventListener? {
        inboxEventListenerLock.lock()
        defer { inboxEventListenerLock.unlock() }
        return inboxEventListener
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
