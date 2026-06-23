import CioMessagingInbox
import SwiftUI
import UIKit

/// Hosts the Visual Notification Inbox overlay (`NotificationInboxOverlay`, a SwiftUI view) in a
/// dedicated, passthrough `UIWindow` so the floating bell + slide-out panel appear app-wide on top of
/// the existing UIKit UI — regardless of which view controller is on screen.
///
/// Why a separate window (not a child of the root VC): the app swaps its root view controller on
/// login/logout, and pushes navigation controllers. A persistent overlay window survives those
/// swaps and always stays above the app content. The window is set just below the system alert level
/// so it floats over normal app windows but never above system alerts.
@available(iOS 15.0, *)
@MainActor
enum InboxOverlayWindow {
    private static var window: PassthroughWindow?

    /// Creates (once) and shows the overlay window for the given scene.
    static func install(in windowScene: UIWindowScene) {
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
private final class PassthroughWindow: UIWindow {
    /// Set by the overlay via `onPanelPresentationChange`. When true, the panel/scrim is on screen.
    var isPanelOpen = false

    /// Approximate hit area of the floating bell — a 56pt button with 16pt padding pinned to the
    /// bottom-trailing safe-area corner (matches `NotificationInboxOverlay`'s layout), plus slop.
    private func bellHitRect() -> CGRect {
        let buttonSize: CGFloat = 56
        let padding: CGFloat = 16
        let slop: CGFloat = 12
        let left = bounds.maxX - safeAreaInsets.right - padding - buttonSize - slop
        let top = bounds.maxY - safeAreaInsets.bottom - padding - buttonSize - slop
        return CGRect(x: left, y: top, width: buttonSize + slop * 2, height: buttonSize + slop * 2)
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
