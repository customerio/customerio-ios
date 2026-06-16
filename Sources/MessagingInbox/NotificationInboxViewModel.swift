import CioInternalCommon
import CioMessagingInApp
import Foundation
#if canImport(SwiftUI)
import SwiftUI

/// Observable state holder backing ``NotificationInboxView``.
///
/// Loads the current inbox once via `getMessages()` and then subscribes to the
/// `messages()` `AsyncStream` for live updates. The stream is driven inside a `Task`
/// owned by this object; the task is cancelled when the view disappears (`stop()`),
/// preventing leaks and unnecessary work while the UI is offscreen.
@available(iOS 13.0, *)
@MainActor
final class NotificationInboxViewModel: ObservableObject {
    /// Latest messages, sorted newest-first by the underlying inbox API.
    @Published private(set) var messages: [InboxMessage] = []

    /// Number of unread messages, used to drive the badge.
    var unreadCount: Int {
        messages.filter { !$0.opened }.count
    }

    /// True when the slide-out panel is visible.
    @Published var isPanelOpen: Bool = false

    private let inbox: NotificationInbox
    private var observationTask: Task<Void, Never>?

    init(inbox: NotificationInbox = MessagingInApp.shared.inbox) {
        self.inbox = inbox
    }

    /// Begins observing the inbox. Safe to call multiple times; subsequent calls are no-ops
    /// while an observation is already running.
    func start() {
        guard observationTask == nil else { return }

        // Capture only the inbox dependency, not the whole view model, until we hop back to main.
        let inbox = inbox
        observationTask = Task { [weak self] in
            // Emit an immediate snapshot so the UI is populated before the first stream event.
            let initial = await inbox.getMessages()
            self?.messages = initial

            for await updated in inbox.messages() {
                if Task.isCancelled { break }
                self?.messages = updated
            }
        }
    }

    /// Stops observing the inbox and releases the backing task.
    func stop() {
        observationTask?.cancel()
        observationTask = nil
    }

    /// Toggles the slide-out panel open/closed.
    func togglePanel() {
        isPanelOpen.toggle()
    }

    /// Marks a message opened/unopened, mirroring its current state.
    func toggleOpened(_ message: InboxMessage) {
        if message.opened {
            inbox.markMessageUnopened(message: message)
        } else {
            inbox.markMessageOpened(message: message)
        }
    }
}
#endif
