import CioInternalCommon
import Foundation
import UserNotifications

// Using an extension on UNUserNotificationCenter is the most reliable way to swizzle its delegate setter.
@available(iOSApplicationExtension, unavailable)
extension UNUserNotificationCenter {
    /// Swizzled implementation of `UNUserNotificationCenter.delegate` setter.
    ///
    /// When the swizzle is active, any assignment to `UNUserNotificationCenter.delegate` routes here.
    /// If the incoming delegate is already ours we pass it straight through to the original setter.
    /// Otherwise we wrap it in a `CioNotificationCenterDelegate` so the SDK stays in the notification
    /// pipeline regardless of what other SDKs or app code assign.
    @objc dynamic func cio_swizzled_setDelegate(delegate: UNUserNotificationCenterDelegate?) {
        let logger = DIGraphShared.shared.logger
        logger.debug("New UNUserNotificationCenter.delegate set. Delegate class: \(String(describing: delegate))")

        if delegate is CioNotificationCenterDelegate {
            // Already our delegate — forward to the original setter.
            cio_swizzled_setDelegate(delegate: delegate)
            return
        }

        guard MessagingPush.moduleConfig.autoTrackPushEvents else {
            // autoTrackPushEvents is disabled — pass the delegate through unchanged.
            cio_swizzled_setDelegate(delegate: delegate)
            return
        }

        // A non-CIO delegate was assigned. Wrap it so we stay in the notification pipeline.
        // installNotificationCenterDelegate will call center.delegate = proxy (a CioNotificationCenterDelegate),
        // which re-enters this method and passes through the guard above.
        MessagingPush.installNotificationCenterDelegate(
            wrapping: delegate,
            centerProvider: { self }
        )
    }
}
