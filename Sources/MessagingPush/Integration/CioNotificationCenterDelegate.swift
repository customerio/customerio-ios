import CioInternalCommon
import UIKit

@available(iOSApplicationExtension, unavailable)
open class CioNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let messagingPush: MessagingPushInstance
    private let config: ConfigInstance?
    private var wrappedNotificationCenterDelegate: UNUserNotificationCenterDelegate?

    public init(
        messagingPush: MessagingPushInstance,
        config: ConfigInstance?,
        wrappedDelegate: UNUserNotificationCenterDelegate?
    ) {
        self.messagingPush = messagingPush
        self.config = config
        self.wrappedNotificationCenterDelegate = wrappedDelegate
        super.init()
    }

    open func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if let wrappedNotificationCenterDelegate = wrappedNotificationCenterDelegate,
           wrappedNotificationCenterDelegate.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:))) {
            // Pass completionHandler directly to support async implementations (e.g. a React Native JS bridge that
            // calls back from the JS thread). A previous wrapper-closure approach tracked whether the handler was
            // called synchronously and provided a fallback if not; that broke async delegates by invoking the
            // handler a second time with the SDK default options.
            // Trade-off: a delegate that returns true from responds(to:) but never calls the handler will now leave
            // it uncalled. No known SDK or framework exhibits this behaviour by default; it would represent a bug
            // in the host app's delegate code.
            wrappedNotificationCenterDelegate.userNotificationCenter?(
                center,
                willPresent: notification,
                withCompletionHandler: completionHandler
            )
            return
        }

        if config?().showPushAppInForeground ?? false {
            if #available(iOS 14.0, *) {
                completionHandler([.list, .banner, .badge, .sound])
            } else {
                completionHandler([.alert, .badge, .sound])
            }
        } else {
            completionHandler([])
        }
    }

    // Function called when a push notification is clicked or swiped away.
    open func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Cast to concrete type since method was removed from protocol
        if let implementation = messagingPush as? MessagingPush {
            _ = implementation.userNotificationCenter(center, didReceive: response)
        }

        if let wrappedNotificationCenterDelegate = wrappedNotificationCenterDelegate,
           wrappedNotificationCenterDelegate.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))) {
            // Pass completionHandler directly to support async implementations (e.g. a React Native JS bridge that
            // calls back from the JS thread). A previous wrapper-closure approach tracked whether the handler was
            // called synchronously and provided a fallback if not; that broke async delegates by invoking the
            // handler a second time.
            // Trade-off: a delegate that returns true from responds(to:) but never calls the handler will now leave
            // it uncalled. No known SDK or framework exhibits this behaviour by default; it would represent a bug
            // in the host app's delegate code.
            wrappedNotificationCenterDelegate.userNotificationCenter?(
                center,
                didReceive: response,
                withCompletionHandler: completionHandler
            )
            return
        }

        completionHandler()
    }

    /// Prevent issues caused by swizzling in various SDKs that check for method existence without using
    /// `responds(to:)` (e.g. FirebaseMessaging). An empty stub ensures the method exists for forwarding.
    open func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        wrappedNotificationCenterDelegate?.userNotificationCenter?(center, openSettingsFor: notification)
    }
}
