import CioInternalCommon
import Foundation
import UserNotifications

@available(iOSApplicationExtension, unavailable)
extension MessagingPush {
    /// Whether `delegate` is the exact process-wide proxy. Two absent optional references are deliberately not
    /// equal here: before the proxy has been published, assigning `nil` is a real clear operation rather than
    /// a pass-through assignment of our proxy.
    static func isInstalledNotificationCenterDelegate(
        _ delegate: UNUserNotificationCenterDelegate?
    ) -> Bool {
        guard let installedProxy = shared.installedNotificationCenterDelegate else { return false }
        return delegate === installedProxy
    }
}

// Using an extension on UNUserNotificationCenter is the most reliable way to swizzle its delegate setter.
@available(iOSApplicationExtension, unavailable)
extension UNUserNotificationCenter {
    /// Swizzled implementation of `UNUserNotificationCenter.delegate` setter.
    ///
    /// When the swizzle is active, any assignment to `UNUserNotificationCenter.delegate` routes here.
    /// If the incoming delegate is the exact shared proxy we pass it straight through to the original setter.
    /// Otherwise we register it as a peer of the SDK's single `CioNotificationCenterDelegate`, which stays
    /// installed as the system delegate. The incoming delegate keeps receiving callbacks — forwarded by the
    /// proxy — and so does every delegate assigned before it, which a plain assignment would have displaced.
    @objc dynamic func cio_swizzled_setDelegate(delegate: UNUserNotificationCenterDelegate?) {
        if MessagingPush.isInstalledNotificationCenterDelegate(delegate) {
            // The exact installed shared proxy — forward to the original setter. A separately constructed public
            // CioNotificationCenterDelegate is external and is registered as a peer below. This guard must run
            // before logger resolution because proxy reassertion occurs under the install lock, and an
            // app-provided logger dispatcher could otherwise reenter that lock.
            cio_swizzled_setDelegate(delegate: delegate)
            return
        }

        let logger = DIGraphShared.shared.logger
        logger.debug("New UNUserNotificationCenter.delegate set. Delegate class: \(String(describing: delegate))")

        guard MessagingPush.moduleConfig.autoTrackPushEvents else {
            // autoTrackPushEvents is disabled — pass the delegate through unchanged.
            cio_swizzled_setDelegate(delegate: delegate)
            return
        }

        // A non-CIO delegate (or `nil`) was assigned. Register it as a peer so we stay in the notification
        // pipeline and no previously assigned delegate is displaced. The original setter is intentionally not
        // called: the proxy stays the installed delegate, and installNotificationCenterDelegate re-asserts it
        // only if something else has replaced it — that assignment re-enters this method and passes through the
        // exact shared-proxy identity guard above.
        MessagingPush.installNotificationCenterDelegate(
            wrapping: delegate,
            centerProvider: { self }
        )
    }
}
