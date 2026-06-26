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
    @ObservedObject private var model: VisualInboxModel

    /// Drives dark-mode branding resolution for the bell chrome.
    @Environment(\.colorScheme) private var colorScheme

    /// True when this view owns the model's lifecycle (standalone use) vs. observing a shared model
    /// owned by ``NotificationInboxOverlay`` (which drives start/stop itself).
    private let ownsModelLifecycle: Bool

    /// Called when the user taps the bell.
    private let onTap: () -> Void

    /// Creates a standalone inbox bell backed by the SDK's shared Visual Inbox data layer.
    /// - Parameter onTap: invoked when the user taps the bell.
    public init(onTap: @escaping () -> Void) {
        _model = ObservedObject(wrappedValue: VisualInboxModel())
        self.ownsModelLifecycle = true
        self.onTap = onTap
    }

    /// Creates a bell observing a shared model (used by ``NotificationInboxOverlay`` so the bell,
    /// panel, and overlay all observe the same state). The shared model's lifecycle is driven by the
    /// owner, so this view does not start/stop it.
    init(model: VisualInboxModel, onTap: @escaping () -> Void) {
        _model = ObservedObject(wrappedValue: model)
        self.ownsModelLifecycle = false
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
        return Button(action: onTap, label: {
            ZStack(alignment: .topTrailing) {
                // Default bundled SF Symbol bell (branding SVG bell is deferred).
                Image(systemName: "bell.fill")
                    .foregroundColor(colors.bellIcon)
                    .frame(width: 56, height: 56)
                    .background(colors.bellBackground)
                    .clipShape(Circle())
                    .shadow(radius: 4)

                if model.unopenedCount > 0 {
                    Text("\(model.unopenedCount)")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(5)
                        .background(colors.badge)
                        .clipShape(Circle())
                        .offset(x: 4, y: -4)
                }
            }
        })
        // `.accessibility(label:)` is the iOS 13-safe form; `.accessibilityLabel` is iOS 14+.
        .accessibility(label: Text(model.unopenedCount > 0 ? "Notifications, \(model.unopenedCount) unread" : "Notifications"))
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
