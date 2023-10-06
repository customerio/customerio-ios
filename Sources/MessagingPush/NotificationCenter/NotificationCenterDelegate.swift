import Foundation
import UserNotifications

@available(iOSApplicationExtension, unavailable)
public class CustomerIOUserNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = CustomerIOUserNotificationCenterDelegate()

    override private init() {}

    // Notification was interacted with.
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        _ = MessagingPush.shared.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
    }
}

@available(iOSApplicationExtension, unavailable)
extension MessagingPush {
    func setupCioPushClickHandling() {
        // When SDKs after ours sets itself up as the UNUserNotificationCenterDelegate, we will still be able to process push notifications.
        swizzle(
            forClass: UNUserNotificationCenter.self,
            original: #selector(setter: UNUserNotificationCenter.delegate),
            new: #selector(UNUserNotificationCenter.cio_swizzle_UNUserNotificationCenter_setDelegate(_:))
        )

        // Set our SDK as the click handler, if there isn't one already set in the app.
        let appNotificationCenter = UNUserNotificationCenter.current()

        if appNotificationCenter.delegate == nil {
            appNotificationCenter.delegate = CustomerIOUserNotificationCenterDelegate.shared

            // if another SDK or host app sets itself as the delegate, our SDK swizzled the delegate setter so we will be able to hook into the logic and still process pushes.
        } else {
            // This handles the case where a delegate may have already been assigned before our SDK is loaded into memory.
            // This re-assignment triggers NotifiationCenter.delegate setter that we swizzled so our SDK can swizzle in its logic.
            appNotificationCenter.delegate = appNotificationCenter.delegate
        }
    }

    @objc func cio_swizzle_didReceive(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        _ = MessagingPush.shared.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)

        // to continue the path
        cio_swizzle_didReceive(center, didReceive: response, withCompletionHandler: completionHandler)
    }
}

@available(iOSApplicationExtension, unavailable)
extension UNUserNotificationCenter {
    @objc func cio_swizzle_UNUserNotificationCenter_setDelegate(_ delegate: UNUserNotificationCenterDelegate) {
        let classForDelegate: AnyClass = type(of: delegate)

        swizzle(
            fromClass: classForDelegate,
            toClass: MessagingPush.self,
            original: #selector(delegate.userNotificationCenter(_:didReceive:withCompletionHandler:)),
            new: #selector(MessagingPush.cio_swizzle_didReceive(_:didReceive:withCompletionHandler:))
        )

        // continue the path
        cio_swizzle_UNUserNotificationCenter_setDelegate(delegate)
    }
}

func swizzle(forClass: AnyClass, original: Selector, new: Selector) {
    guard let originalMethod = class_getInstanceMethod(forClass, original) else { return }
    guard let swizzledMethod = class_getInstanceMethod(forClass, new) else { return }
    method_exchangeImplementations(originalMethod, swizzledMethod)
}

func swizzle(fromClass: AnyClass, toClass: AnyClass, original: Selector, new: Selector) {
    guard let originalMethod = class_getInstanceMethod(fromClass, original) else { return }
    guard let swizzledMethod = class_getInstanceMethod(toClass, new) else { return }
    method_exchangeImplementations(originalMethod, swizzledMethod)
}
