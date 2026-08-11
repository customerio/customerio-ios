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
public struct NotificationInboxBell: View {
    /// Owns the model for standalone use. `@State` intentionally preserves the existing ownership
    /// behavior; `@ObservedObject` would not own the value and could replace a started model during
    /// parent updates. Moving to another ownership wrapper requires separate lifecycle validation.
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
        return Button(action: onTap, label: {
            ZStack(alignment: .topTrailing) {
                bellGlyph(colors: colors)
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
                }
            }
        })
        .accessibility(label: Text(showsUnreadCount ? "Notifications, \(model.unopenedCount) unread" : "Notifications"))
    }

    /// The bell glyph: the workspace's branding SVG (`floatingIcon.svg`) when present and parseable
    /// (pre-built once by the model), otherwise the bundled default bell asset. Both are tinted with
    /// the branding glyph color.
    @ViewBuilder
    private func bellGlyph(colors: ResolvedInboxColors) -> some View {
        if let glyph = model.bellGlyph {
            // Fill each <path> INDEPENDENTLY (like the browser) with its OWN declared fill rule so
            // overlapping paths don't flip each other's winding parity (MBL-2123). Uniform tint → the
            // stack reads as one glyph.
            ZStack {
                ForEach(Array(glyph.subpaths.enumerated()), id: \.offset) { _, subpath in
                    InboxBellIcon(subpath: subpath.path, viewBox: glyph.viewBox)
                        .fill(colors.bellIcon, style: FillStyle(eoFill: subpath.usesEvenOddFill))
                }
            }
        } else {
            Image("cio-inbox-bell", bundle: .cioInboxResources)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(colors.bellIcon)
        }
    }
}

/// Starts/stops the shared model only when this view owns the lifecycle. Centralizes the
/// `onAppear`/`onDisappear` so the bell and panel can each conditionally drive it.
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
