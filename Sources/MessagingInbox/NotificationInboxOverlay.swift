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
/// loads the current messages and then observes the live `messages()` stream for updates. When the
/// inbox is empty, the view renders nothing (no button, no badge, no panel).
///
/// - Note: This is the Milestone 1 placeholder UI. Rows show plain text derived from
///   ``InboxMessage`` fields and a read/unread indicator; rich/templated rendering lands later.
@available(iOS 13.0, *)
public struct NotificationInboxOverlay: View {
    @ObservedObject private var viewModel: NotificationInboxViewModel

    /// Creates an inbox view backed by the SDK's shared inbox.
    public init() {
        self.init(viewModel: NotificationInboxViewModel())
    }

    init(viewModel: NotificationInboxViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // The slide-out panel sits behind the floating button so the button stays tappable.
            if viewModel.isPanelOpen {
                panel
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Render no chrome at all when there are no messages.
            if !viewModel.messages.isEmpty {
                floatingButton
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    // MARK: - Floating button + badge

    private var floatingButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                viewModel.togglePanel()
            }
        }, label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.accentColor)
                    .clipShape(Circle())
                    .shadow(radius: 4)

                if viewModel.unreadCount > 0 {
                    Text("\(viewModel.unreadCount)")
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
                    ForEach(viewModel.messages, id: \.queueId) { message in
                        InboxMessageRow(message: message) {
                            viewModel.toggleOpened(message)
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
        .padding(.bottom, 88) // keep the panel clear of the floating button
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
#endif
