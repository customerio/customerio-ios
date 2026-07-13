import CioInternalCommon
@_spi(VisualInbox) import CioMessagingInApp
import Foundation
#if canImport(SwiftUI)
import SwiftUI

/// A SwiftUI overlay that renders the Visual Notification Inbox on top of your app.
///
/// Mount it anywhere in your hierarchy (typically pinned to a corner via a `ZStack`). It renders a
/// floating bell button with an unread-count badge; tapping the bell presents the inbox message list
/// (each message rendered natively via **Jist** from the server templates + branding theme) in a
/// native bottom **sheet** with system detents (medium / large) and a drag indicator.
///
/// This is the convenience all-in-one: it composes ``NotificationInboxBell`` (the bell) with a
/// system sheet hosting ``NotificationInboxView`` (the message list) over a shared data model, adding
/// the floating placement (per branding `patterns.inbox.position`). For custom placement or your own
/// presentation, use those two views directly.
///
/// Because it relies on SwiftUI's `presentationDetents`, the overlay requires **iOS 16+**. For iOS 15
/// hosts, compose ``NotificationInboxBell`` + present ``NotificationInboxView`` yourself.
///
/// ## Usage
/// ```swift
/// ZStack { MyDashboard(); NotificationInboxOverlay() }
/// ```
@available(iOS 16.0, *)
public struct NotificationInboxOverlay: View {
    @StateObject private var model: VisualInboxModel

    /// True while the inbox sheet is presented.
    @State private var isInboxPresented = false

    /// Creates an inbox overlay backed by the SDK's shared Visual Inbox data layer.
    public init() {
        _model = StateObject(wrappedValue: VisualInboxModel())
    }

    /// Creates an inbox overlay backed by the supplied model. Used by tests/previews to inject a fake.
    init(model: VisualInboxModel) {
        _model = StateObject(wrappedValue: model)
    }

    public var body: some View {
        // Bell anchor is branding-driven (`patterns.inbox.position`); defaults to bottom-right.
        let bellPosition = InboxBellPosition.resolve(model.chrome?.position)
        // Bell is shown unless the inbox is hidden (the bell view hides itself based on chrome state);
        // tapping it presents the inbox list in a native sheet with system detents.
        //
        // The bell + lifecycle live in a ZStack anchored by a stable, non-interactive `Color.clear`.
        // This matters: when the inbox goes hidden the bell renders nothing, and if `onDisappear` were
        // attached to the bell it would fire and `model.stop()` would cancel the data subscription
        // permanently — so a later message could never re-show the bell. The always-present clear
        // anchor keeps the overlay mounted (subscription alive) while the bell is hidden, and
        // `allowsHitTesting(false)` preserves touch passthrough to the content behind the overlay.
        return ZStack(alignment: bellPosition.alignment) {
            Color.clear
                .allowsHitTesting(false)
            NotificationInboxBell(model: model) {
                isInboxPresented = true
            }
            .padding(16)
        }
        // The overlay owns the shared model's lifecycle (the bell/sheet observe it but don't drive it).
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        // If the inbox transitions to hidden while the sheet is open, dismiss it so it doesn't linger.
        .onChange(of: model.showsChrome) { visible in
            if !visible { isInboxPresented = false }
        }
        // Auto-mark-opened (item 8): when the sheet is presented, mark the visible messages opened
        // (deduped inside the model so a message is never marked twice).
        .onChange(of: isInboxPresented) { presented in
            if presented { model.markVisibleMessagesOpened() }
        }
        // System sheet with medium/large detents + grabber — no header (matches web parity). The list
        // shares this overlay's model, so bell and sheet observe the same state.
        .sheet(isPresented: $isInboxPresented) {
            // Dismiss the sheet after a navigation action so the opened screen (deep link / URL) isn't
            // left behind the inbox.
            NotificationInboxView(model: model, onNavigate: { isInboxPresented = false })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}
#endif
