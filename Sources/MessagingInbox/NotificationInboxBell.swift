import CioInternalCommon
@_spi(VisualInbox) import CioMessagingInApp
import Foundation
#if canImport(SwiftUI)
import SwiftUI

/// A standalone, placeable Visual Notification Inbox bell button with an unread-count badge.
///
/// Unlike ``NotificationInboxOverlay`` (which owns the floating + slide-out chrome), this view is
/// JUST the bell. Place it anywhere — a navigation bar, a toolbar, a custom dashboard — and wire its
/// `onTap` to whatever presents your inbox (e.g. push a screen embedding ``NotificationInboxView``).
///
/// It reads the unread count reactively from the SDK's shared Visual Inbox data layer and hides
/// itself when the inbox is hidden (no enabled inbox / nothing to show).
///
/// ## Usage
/// ```swift
/// NotificationInboxBell { showInbox = true }
/// ```
@available(iOS 13.0, *)
public struct NotificationInboxBell: View {
    /// Owns the model for standalone use. `@State` rather than `@ObservedObject` so SwiftUI keeps the
    /// instance across view reconstruction; `@StateObject` is iOS 14+ and this view is public on
    /// iOS 13. See ``NotificationInboxView`` for the full rationale.
    @State private var model = VisualInboxModel()

    private let onTap: () -> Void

    /// Creates a standalone inbox bell backed by the SDK's shared Visual Inbox data layer.
    /// - Parameter onTap: invoked when the user taps the bell.
    public init(onTap: @escaping () -> Void) {
        self.onTap = onTap
    }

    public var body: some View {
        InboxBellView(model: model, ownsModelLifecycle: true, onTap: onTap)
    }
}

/// Renders the bell for a model it does not own. Always constructed with an explicit model — either
/// the shared one from ``NotificationInboxOverlay`` or the one ``NotificationInboxBell`` owns.
@available(iOS 13.0, *)
struct InboxBellView: View {
    @ObservedObject private var model: VisualInboxModel

    /// Drives dark-mode branding resolution for the bell chrome.
    @Environment(\.colorScheme) private var colorScheme

    /// True when this view owns the model's lifecycle (standalone use) vs. observing a shared model
    /// owned by ``NotificationInboxOverlay`` (which drives start/stop itself).
    private let ownsModelLifecycle: Bool

    /// Called when the user taps the bell.
    private let onTap: () -> Void

    /// Creates a bell observing a shared model (used by ``NotificationInboxOverlay`` so the bell,
    /// panel, and overlay all observe the same state). The shared model's lifecycle is driven by the
    /// owner, so this view does not start/stop it.
    init(model: VisualInboxModel, ownsModelLifecycle: Bool = false, onTap: @escaping () -> Void) {
        _model = ObservedObject(wrappedValue: model)
        self.ownsModelLifecycle = ownsModelLifecycle
        self.onTap = onTap
    }

    public var body: some View {
        Group {
            if model.showsChrome {
                button
            }
        }
        .modifier(LifecycleModifier(model: model, enabled: ownsModelLifecycle))
    }

    private var button: some View {
        // Branding-first chrome colors (bell fill / glyph / badge), with a contrast-aware glyph
        // fallback so a light branded bell never renders a white glyph on a white circle.
        let colors = ResolvedInboxColors.resolve(chrome: model.chrome, isDark: colorScheme == .dark)
        // The unread count is surfaced (badge + VoiceOver) only when there ARE unopened messages AND
        // branding's `unreadIndicator.showAlert` allows it (nil → show, matching web parity). Both the
        // visible badge and the accessibility label key off this, so VoiceOver never announces a count
        // the workspace chose to hide.
        let showsUnreadCount = model.unopenedCount > 0 && (model.chrome?.showUnreadBadge ?? true)
        // The SDK ships no strings of its own: the label comes from the host's
        // `NotificationInboxAccessibilityLabels` — the count-aware closure while the badge shows
        // (falling back to the plain bell label), the plain bell label otherwise, or none at all when
        // unconfigured, leaving an unnamed-but-reachable button. VoiceOver never announces a count the
        // workspace chose to hide, because `showsUnreadCount` gates both.
        let labels = model.accessibilityLabels
        let accessibilityLabel = showsUnreadCount
            ? labels.bellWithUnreadCount?(model.unopenedCount) ?? labels.bell
            : labels.bell
        return Button(action: onTap, label: {
            ZStack(alignment: .topTrailing) {
                InboxBellGlyphView(glyph: model.bellGlyph, tint: colors.bellIcon)
                    .frame(width: 26, height: 26)
                    .frame(width: 56, height: 56)
                    .background(colors.bellBackground)
                    .clipShape(Circle())
                    .shadow(radius: 4)

                if showsUnreadCount {
                    // Badge count text color + size come from branding (`unreadIndicator.text`,
                    // MBL-2126), falling back to white / the caption size when unset.
                    // Geometry mirrors web (`#gist-inbox-badge`): a 20pt-tall stadium (Capsule,
                    // radius = height/2) with min-width 20 and 6pt horizontal padding, so a single
                    // digit is a circle and multi-digit counts grow horizontally rather than forcing
                    // a full circle (MBL-2127). Offset (4, -4) matches web's top:-4/right:-4.
                    Text("\(model.unopenedCount)")
                        .font(colors.badgeTextSize.map { Font.system(size: $0) } ?? .caption)
                        .foregroundColor(colors.badgeText)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(colors.badge)
                        .clipShape(Capsule())
                        .offset(x: 4, y: -4)
                        // The badge is decorative: a button folds its children's text into its own
                        // label, so leaving the digits visible to VoiceOver would append a bare number
                        // to an otherwise unnamed bell. The count reaches VoiceOver only through the
                        // host's `bellWithUnreadCount` label.
                        .accessibility(hidden: true)
                }
            }
        })
        .inboxAccessibilityLabel(accessibilityLabel)
    }
}

/// Starts/stops the shared model only when this view owns the lifecycle. Centralizes the
/// `onAppear`/`onDisappear` so the bell and panel can each conditionally drive it.
@available(iOS 13.0, *)
struct LifecycleModifier: ViewModifier {
    @ObservedObject var model: VisualInboxModel
    let enabled: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { if enabled { model.start() } }
            .onDisappear { if enabled { model.stop() } }
    }
}
#endif
