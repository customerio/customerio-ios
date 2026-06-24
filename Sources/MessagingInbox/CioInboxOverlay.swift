#if canImport(UIKit)
import SwiftUI
import UIKit

/// Convenience entry point for mounting the Visual Notification Inbox overlay app-wide from a UIKit
/// host.
///
/// It hosts ``NotificationInboxOverlay`` in a dedicated, passthrough `UIWindow` so the floating bell +
/// slide-out panel appear on top of the existing UIKit UI regardless of which view controller is on
/// screen, and survive root-view-controller swaps (login/logout) and navigation.
///
/// ## Usage
/// ```swift
/// func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
///     guard let windowScene = scene as? UIWindowScene else { return }
///     if #available(iOS 15.0, *) { CioInboxOverlay.install(in: windowScene) }
/// }
/// ```
///
/// SwiftUI host (no UIKit window needed): place ``NotificationInboxOverlay`` in a `ZStack` instead.
@available(iOS 15.0, *)
@MainActor
public enum CioInboxOverlay {
    /// The single overlay window, retained so it stays on screen for the app's lifetime.
    private static var window: PassthroughWindow?

    /// Creates (once) and shows the overlay window for the given scene. Idempotent — a second call is
    /// a no-op while a window already exists.
    public static func install(in windowScene: UIWindowScene) {
        guard window == nil else { return }

        let overlayWindow = PassthroughWindow(windowScene: windowScene)
        // The overlay tells the window when the panel opens/closes so the window can switch between
        // full-screen capture (panel open) and bell-only capture (panel closed). See PassthroughWindow.
        let hosting = UIHostingController(
            rootView: NotificationInboxOverlay(
                onPanelPresentationChange: { [weak overlayWindow] open in
                    overlayWindow?.isPanelOpen = open
                }
            )
        )
        // Clear background so the app shows through everywhere the overlay isn't drawing.
        hosting.view.backgroundColor = .clear

        overlayWindow.rootViewController = hosting
        overlayWindow.backgroundColor = .clear
        // Float above app content but below system alerts.
        overlayWindow.windowLevel = .alert - 1
        overlayWindow.isHidden = false
        window = overlayWindow
    }
}

/// Passthrough overlay window.
///
/// SwiftUI routes the bell/scrim tap gestures *through* the hosting controller's root view (it does
/// not create a distinct child `UIView` per control), so the naive "pass through unless the hit is a
/// non-root subview" approach would starve the bell of touches. Instead we decide by panel state +
/// geometry, and return the hit view (even when it is the hosting root) so SwiftUI receives the touch:
///  - **panel open** → capture ALL touches; the SwiftUI scrim blocks click-through and a tap on it
///    closes the panel.
///  - **panel closed** → capture only the floating bell's region (bottom-trailing); every other touch
///    falls through to the app window beneath, keeping the rest of the app usable.
@available(iOS 15.0, *)
final class PassthroughWindow: UIWindow {
    /// Set by the overlay via `onPanelPresentationChange`. When true, the panel/scrim is on screen.
    var isPanelOpen = false

    /// Approximate hit area of the floating bell — a 56pt button with 16pt padding pinned to the
    /// bottom-trailing safe-area corner (matches `NotificationInboxOverlay`'s layout), plus slop.
    private func bellHitRect() -> CGRect {
        let buttonSize: CGFloat = 56
        let padding: CGFloat = 16
        let slop: CGFloat = 12
        // The unread badge is drawn offset beyond the bell's top-trailing corner, so extend the hit
        // area up and toward the trailing edge so taps on the badge hit the overlay too (not the app).
        let badgeAllowance: CGFloat = 20
        let left = bounds.maxX - safeAreaInsets.right - padding - buttonSize - slop
        let top = bounds.maxY - safeAreaInsets.bottom - padding - buttonSize - slop - badgeAllowance
        return CGRect(x: left, y: top, width: buttonSize + slop * 2 + badgeAllowance, height: buttonSize + slop * 2 + badgeAllowance)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if isPanelOpen {
            // Panel visible: capture everything so the scrim blocks click-through to the app.
            return hit
        }
        // Panel closed: only the bell is interactive; everything else passes through to the app.
        return bellHitRect().contains(point) ? hit : nil
    }
}
#endif
