import CioInternalCommon
import CioMessagingInApp
import Foundation
#if canImport(SwiftUI)
import SwiftUI

/// A SwiftUI overlay that renders a visual notification inbox on top of your app.
///
/// Mount this overlay anywhere in your hierarchy (typically pinned to a corner via a `ZStack`
/// or as a full-screen overlay). It renders:
/// * a floating button with an unread-count badge, and
/// * a slide-out panel listing inbox messages as simple placeholder rows. The panel spans the
///   screen width minus horizontal margins, capped at a tablet-friendly maximum width.
///
/// State is driven entirely by the headless inbox API (`MessagingInApp.shared.inbox`): the view
/// loads the current messages and then observes the live `messages()` stream for updates. The
/// floating button is always shown so the inbox stays reachable even when empty; the unread badge
/// only appears when there are unread messages, and an empty inbox opens to an empty panel.
///
/// - Note: This is the Milestone 1 placeholder UI. Rows show plain text derived from
///   ``InboxMessage`` fields and a read/unread indicator; rich/templated rendering lands later.
///
/// ## Usage
/// Mount it in a `ZStack` (or as an `.overlay`) so it floats over your existing content:
/// ```swift
/// ZStack { MyDashboard(); NotificationInboxOverlay() }
/// ```
@available(iOS 13.0, *)
public struct NotificationInboxOverlay: View {
    /// Latest messages, sorted newest-first by the underlying inbox API.
    @State private var messages: [InboxMessage] = []

    /// True when the slide-out panel is visible.
    @State private var isPanelOpen: Bool = false

    /// Backing task for the live `messages()` observation; cancelled when the view disappears.
    @State private var observationTask: Task<Void, Never>?

    /// Vertical inset that keeps the slide-out panel clear of the floating button.
    private let panelBottomInset: CGFloat = 88

    private let inbox: NotificationInbox

    /// Creates an inbox overlay backed by the SDK's shared inbox.
    public init() {
        self.inbox = MessagingInApp.shared.inbox
    }

    /// Creates an inbox overlay backed by the supplied inbox. Used by tests to inject a fake.
    init(inbox: NotificationInbox) {
        self.inbox = inbox
    }

    /// Number of unread messages in the given list. Pure function so it can be unit tested
    /// without driving SwiftUI state.
    static func unreadCount(in messages: [InboxMessage]) -> Int {
        messages.filter { !$0.opened }.count
    }

    /// Number of unread messages, used to drive the badge.
    private var unreadCount: Int {
        Self.unreadCount(in: messages)
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // The slide-out panel sits behind the floating button so the button stays tappable.
            if isPanelOpen {
                panel
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Always show the button so the inbox is reachable even when empty.
            floatingButton
        }
        .onAppear(perform: startObserving)
        .onDisappear(perform: stopObserving)
    }

    // MARK: - Inbox observation

    /// Begins observing the inbox. Safe to call multiple times; subsequent calls are no-ops
    /// while an observation is already running. Emits an immediate snapshot, then follows the
    /// live `messages()` stream until the view disappears.
    private func startObserving() {
        guard observationTask == nil else { return }

        // Capture only the inbox dependency; state updates hop to the main actor.
        let inbox = inbox
        observationTask = Task { @MainActor in
            messages = await inbox.getMessages()

            for await updated in inbox.messages() {
                if Task.isCancelled { break }
                messages = updated
            }
        }
    }

    /// Stops observing the inbox and releases the backing task.
    private func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }

    /// Marks a message opened/unopened, mirroring its current state.
    func toggleOpened(_ message: InboxMessage) {
        if message.opened {
            inbox.markMessageUnopened(message: message)
        } else {
            inbox.markMessageOpened(message: message)
        }
    }

    // MARK: - Floating button + badge

    private var floatingButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                isPanelOpen.toggle()
            }
        }, label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.accentColor)
                    .clipShape(Circle())
                    .shadow(radius: 4)

                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(5)
                        .background(Color.red)
                        .clipShape(Circle())
                        .offset(x: 4, y: -4)
                }
            }
        })
        .padding(16)
        // `.accessibility(label:)` is the iOS 13-safe form; `.accessibilityLabel` is iOS 14+.
        .accessibility(label: Text(unreadCount > 0 ? "Notifications, \(unreadCount) unread" : "Notifications"))
    }

    // MARK: - Slide-out panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Inbox")
                .font(.headline)
                .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(messages, id: \.queueId) { message in
                        InboxMessageRow(message: message) {
                            toggleOpened(message)
                        }
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: 480, maxHeight: 480, alignment: .top)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, panelBottomInset)
    }
}

/// A simple placeholder row for a single inbox message.
///
/// Renders plain `Text` derived from ``InboxMessage`` fields plus a read/unread indicator.
/// No Jist/templated rendering — that arrives in a later milestone.
@available(iOS 13.0, *)
struct InboxMessageRow: View {
    let message: InboxMessage
    let onToggleOpened: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Unread indicator dot.
            Circle()
                .fill(message.opened ? Color.clear : Color.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(message.queueId)
                    .font(.subheadline)
                    .fontWeight(message.opened ? .regular : .semibold)
                Text(message.type)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onToggleOpened) {
                Text(message.opened ? "Mark unread" : "Mark read")
                    .font(.caption)
            }
            .accessibility(label: Text(message.opened ? "Mark as unread" : "Mark as read"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
#endif
