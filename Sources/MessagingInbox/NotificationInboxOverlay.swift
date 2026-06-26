import CioInternalCommon
@_spi(VisualInbox) import CioMessagingInApp
import Foundation
#if canImport(SwiftUI)
import SwiftUI

/// A SwiftUI overlay that renders the Visual Notification Inbox on top of your app.
///
/// Mount it anywhere in your hierarchy (typically pinned to a corner via a `ZStack`). It renders a
/// floating bell button with an unread-count badge plus a slide-out panel that lists inbox messages,
/// each rendered natively via **Jist** from the server-provided templates + branding theme.
///
/// This is the convenience all-in-one: it composes ``NotificationInboxBell`` (the bell) and
/// ``NotificationInboxView`` (the message list) over a shared data model, adding the floating
/// placement, slide-out animation, and tap-to-dismiss scrim. For custom placement, use those two
/// views directly.
///
/// ## Usage
/// ```swift
/// ZStack { MyDashboard(); NotificationInboxOverlay() }
/// ```
@available(iOS 13.0, *)
public struct NotificationInboxOverlay: View {
    @StateObject private var model: VisualInboxModel

    /// Drives dark-mode branding resolution for the panel chrome.
    @Environment(\.colorScheme) private var colorScheme

    /// True when the slide-out panel is visible.
    @State private var isPanelOpen: Bool = false

    /// Vertical inset that keeps the slide-out panel clear of the floating button.
    private let panelBottomInset: CGFloat = 88

    /// Called whenever the slide-out panel opens (`true`) or closes (`false`). Hosts that mount the
    /// overlay in a passthrough window use this to capture touches full-screen while the panel is
    /// open (so the scrim blocks click-through) and pass through when it's closed.
    private let onPanelPresentationChange: ((Bool) -> Void)?

    /// Creates an inbox overlay backed by the SDK's shared Visual Inbox data layer.
    /// - Parameter onPanelPresentationChange: optional callback invoked when the panel opens/closes.
    public init(onPanelPresentationChange: ((Bool) -> Void)? = nil) {
        _model = StateObject(wrappedValue: VisualInboxModel())
        self.onPanelPresentationChange = onPanelPresentationChange
    }

    /// Creates an inbox overlay backed by the supplied model. Used by tests/previews to inject a fake.
    init(model: VisualInboxModel, onPanelPresentationChange: ((Bool) -> Void)? = nil) {
        _model = StateObject(wrappedValue: model)
        self.onPanelPresentationChange = onPanelPresentationChange
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Scrim (item 10): captures touches behind the panel so taps don't pass through to the
            // host app. Tapping the scrim closes the panel. Only present while open AND chrome is
            // shown — a hidden inbox hides all chrome, including an open panel/scrim.
            if isPanelOpen, model.showsChrome {
                // Scrim opacity 0.32 for cross-platform parity (Android uses the same value).
                Color.black.opacity(0.32)
                    .ignoresSafeAreaCompat()
                    .contentShape(Rectangle())
                    .onTapGesture { setPanel(open: false) }
                    .transition(.opacity)
            }

            // The slide-out panel sits above the scrim but behind the floating button.
            if isPanelOpen, model.showsChrome {
                panel
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Bell is shown unless the inbox is hidden (item 11: hidden → no chrome). The bell view
            // hides itself based on chrome state; it observes the SAME model as the panel.
            NotificationInboxBell(model: model) { setPanel(open: !isPanelOpen) }
                .padding(16)
        }
        // Fill the host so bottom-trailing alignment pins the button to the bottom-right corner.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        // The overlay owns the shared model's lifecycle (the bell/panel observe it but don't drive it).
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        // If the inbox transitions to hidden while the panel is open, close it so it doesn't linger
        // (and doesn't silently reappear if the inbox becomes visible again).
        .onChange(of: model.showsChrome) { visible in
            if !visible, isPanelOpen { isPanelOpen = false }
            // Re-notify when chrome visibility flips: if the inbox goes hidden while the panel flag is
            // still settling, the host must stop full-screen capture so touches aren't swallowed with
            // nothing on screen.
            notifyPanelPresentation()
        }
        // Notify the host of panel presentation so a passthrough-window mount can toggle full-screen
        // touch capture (presented → scrim blocks click-through; not → pass through).
        .onChange(of: isPanelOpen) { _ in
            notifyPanelPresentation()
        }
    }

    /// The panel is "presented" (host should capture full-screen touches) only when it is open AND the
    /// inbox chrome is shown. Keying the host callback off BOTH prevents leaving touch capture on after
    /// the inbox goes hidden while `isPanelOpen` is still true.
    private func notifyPanelPresentation() {
        onPanelPresentationChange?(isPanelOpen && model.showsChrome)
    }

    private func setPanel(open: Bool) {
        withAnimation(.easeInOut(duration: 0.3)) {
            isPanelOpen = open
        }
        // Auto-mark-opened (item 8): when the panel becomes visible, mark the visible messages
        // opened (deduped inside the model so a message is never marked twice).
        if open {
            model.markVisibleMessagesOpened()
        }
    }

    // MARK: - Slide-out panel (items 6, 7, 11)

    private var panel: some View {
        // Branding-first panel surface + corner radius (falls back to the system background / 12pt).
        let colors = ResolvedInboxColors.resolve(chrome: model.chrome, isDark: colorScheme == .dark)
        // No header (title / close button) — matches web. The panel closes via the scrim tap or by
        // tapping the bell again. The panel CONTENT is the embeddable `NotificationInboxView`, sharing
        // this overlay's model (so bell, panel, and overlay all observe the same state).
        return VStack(alignment: .leading, spacing: 0) {
            NotificationInboxView(model: model)
        }
        .frame(maxWidth: 480, maxHeight: .infinity, alignment: .top)
        .background(colors.panelBackground)
        .cornerRadius(colors.cornerRadius)
        .shadow(radius: 8)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, panelBottomInset)
    }
}

/// Cross-version `ignoresSafeArea` helper (the modern modifier is iOS 14+; `edgesIgnoringSafeArea`
/// covers iOS 13).
@available(iOS 13.0, *)
extension View {
    @ViewBuilder
    func ignoresSafeAreaCompat() -> some View {
        if #available(iOS 14.0, *) {
            ignoresSafeArea()
        } else {
            edgesIgnoringSafeArea(.all)
        }
    }
}
#endif
