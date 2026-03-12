import CioInternalCommon
import Foundation
import UserNotifications

/// Manages UNUserNotificationCenter delegate registration, replacing the AppDelegate-based integration.
@available(iOSApplicationExtension, unavailable)
// sourcery: AutoMockable
protocol PushNotificationCenterRegistrar {
    /// Captures any existing UNUserNotificationCenter delegate into the push handler proxy,
    /// then registers the SDK as the sole delegate.
    /// Call this during SDK initialization when `autoTrackPushEvents` is enabled.
    func activate()
}

/// Sets the SDK as the sole UNUserNotificationCenter delegate on SDK initialization,
/// capturing any previously registered delegate into the push event handler proxy so it
/// continues to receive forwarded events. This replaces the AppDelegate subclassing
/// and swizzling-based integration approaches.
@available(iOSApplicationExtension, unavailable)
// sourcery: InjectRegisterShared = "PushNotificationCenterRegistrar"
// sourcery: InjectSingleton
class PushNotificationCenterRegistrarImpl: NSObject, UNUserNotificationCenterDelegate,
    PushNotificationCenterRegistrar
{
    private let pushEventHandler: PushEventHandler
    private let pushEventHandlerProxy: PushEventHandlerProxy
    private var userNotificationCenter: UserNotificationCenter

    init(
        pushEventHandler: PushEventHandler,
        pushEventHandlerProxy: PushEventHandlerProxy,
        userNotificationCenter: UserNotificationCenter
    ) {
        self.pushEventHandler = pushEventHandler
        self.pushEventHandlerProxy = pushEventHandlerProxy
        self.userNotificationCenter = userNotificationCenter
    }

    func activate() {
        if let existingDelegate = userNotificationCenter.currentDelegate {
            pushEventHandlerProxy.addPushEventHandler(
                UNUserNotificationCenterDelegateWrapper(delegate: existingDelegate)
            )
        }
        userNotificationCenter.currentDelegate = self
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        pushEventHandler.shouldDisplayPushAppInForeground(
            UNNotificationWrapper(notification: notification)
        ) { shouldShowPush in
            if shouldShowPush {
                if #available(iOS 14.0, *) {
                    completionHandler([.list, .banner, .badge, .sound])
                } else {
                    completionHandler([.alert, .badge, .sound])
                }
            } else {
                completionHandler([])
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        pushEventHandler.onPushAction(
            UNNotificationResponseWrapper(response: response), completionHandler: completionHandler)
    }
}
