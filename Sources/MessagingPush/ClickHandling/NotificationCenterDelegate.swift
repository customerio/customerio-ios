import UserNotifications

@available(iOSApplicationExtension, unavailable)
public class CustomerIOUserNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = CustomerIOUserNotificationCenterDelegate()

    override private init() {}

    public static func setupCioPushClickHandling() {
        UNUserNotificationCenter.current().setupCioPushClickHandling()

        // Set our SDK as the click handler, if there isn't one already set in the app.
        if UNUserNotificationCenter.current().delegate == nil {
            UNUserNotificationCenter.current().delegate = CustomerIOUserNotificationCenterDelegate.shared

            // if another SDK or host app sets itself as the delegate, our SDK swizzled the delegate setter so we will be able to hook into the logic and still process pushes.
        } else {
            // This handles the case where a delegate may have already been assigned before our SDK is loaded into memory.
            // This re-assignment triggers NotifiationCenter.delegate setter that we swizzled so our SDK can swizzle in its logic.
            UNUserNotificationCenter.current().delegate = UNUserNotificationCenter.current().delegate
        }
    }

    public func setupSwizzling(delegate: UNUserNotificationCenterDelegate) {
        if delegate is CustomerIOUserNotificationCenterDelegate {
            return // avoid infinite loop. we dont want to swizzle our own delegate to avoid duplicate calls for push handling.
        }

        swizzle(
            targetClass: type(of: delegate),
            targetSelector: #selector(userNotificationCenter(_:didReceive:withCompletionHandler:)),
            myClass: CustomerIOUserNotificationCenterDelegate.self,
            mySelector: #selector(cio_swizzle_didReceive(_:didReceive:withCompletionHandler:))
        )
    }

    // Notification was interacted with.
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        _ = MessagingPush.shared.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
    }

    // called when a push is clicked.
    @objc dynamic func cio_swizzle_didReceive(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        _ = MessagingPush.shared.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)

        // TODO: duplicate metrics could be reported because we might be swizzling multiple delegates and so this function gets called X number of times.
        // https://github.com/customerio/issues/issues/11150 should we do this?

        // continue swizzle
        cio_swizzle_didReceive(center, didReceive: response, withCompletionHandler: completionHandler)
    }
}
