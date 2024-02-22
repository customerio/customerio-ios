import CioInternalCommon
import Foundation
import UserNotifications

/**
 The iOS framework, `UserNotifications`, is abstracted away from the SDK codebase.

 This file is the connection between our SDK and `UserNotifications`.
 In production, iOS will call functions in this file. Those requests are then forwarded onto the abstracted code in the SDK to perform all of the logic.
 */
@available(iOSApplicationExtension, unavailable)
protocol UserNotificationsFrameworkAdapter {
    // A reference to an instance of UNUserNotificationCenterDelegate that we can provide to iOS in production.
    var delegate: UNUserNotificationCenterDelegate { get }

    func beginListeningNewNotificationCenterDelegateSet()

    // Called when a new `UNUserNotificationCenterDelegate` is set on the host app. Our Swizzling is what calls this function.
    func newNotificationCenterDelegateSet(_ newDelegate: UNUserNotificationCenterDelegate?)
}

/**
 Keep this class small and simple because it is only able to be tested in QA testing. All logic for handling push events should be in the rest of the code base that has automated tests around it.
 */
@available(iOSApplicationExtension, unavailable)
// sourcery: InjectRegisterShared = "UserNotificationsFrameworkAdapter"
// sourcery: InjectSingleton
class UserNotificationsFrameworkAdapterImpl: NSObject, UNUserNotificationCenterDelegate, UserNotificationsFrameworkAdapter {
    private var pushEventHandler: PushEventHandler
    private var userNotificationCenter: UserNotificationCenter
    private var notificationCenterDelegateProxy: PushEventHandlerProxy

    init(
        pushEventHandler: PushEventHandler,
        userNotificationCenter: UserNotificationCenter,
        notificationCenterDelegateProxy: PushEventHandlerProxy
    ) {
        self.pushEventHandler = pushEventHandler
        self.userNotificationCenter = userNotificationCenter
        self.notificationCenterDelegateProxy = notificationCenterDelegateProxy
    }

    var delegate: UNUserNotificationCenterDelegate {
        self
    }

    // MARK: Swizzling to get notified when a new delegate is set on host app.

    // The swizzling is tightly coupled to the UserNotitications framework. So, the swizzling is housed in this file.

    func beginListeningNewNotificationCenterDelegateSet() {
        // Sets up swizzling of `UNUserNotificationCenter.current().delegate` setter to get notified when a new delegate is set on host app.
        swizzle(
            forClass: UNUserNotificationCenter.self,
            original: #selector(setter: UNUserNotificationCenter.delegate),
            new: #selector(UNUserNotificationCenter.cio_swizzled_setDelegate(delegate:))
        )

        // This re-assignment triggers NotifiationCenter.delegate setter that we swizzled. We want to run this logic now in case a delegate is already set before the CIO SDK is initialized.
        userNotificationCenter.currentDelegate = userNotificationCenter.currentDelegate
    }

    func newNotificationCenterDelegateSet(_ newDelegate: UNUserNotificationCenterDelegate?) {
        guard let newDelegate = newDelegate else {
            return
        }

        notificationCenterDelegateProxy.addPushEventHandler(UNUserNotificationCenterDelegateWrapper(delegate: newDelegate))
    }

    // MARK: UNUserNotificationCenterDelegate functions.

    // Functions called by iOS framework, `UserNotifications`. This adapter class simply passes these requests to other code in our SDK where the logic exists.
    // Convert UserNotifications files into abstracted data types that our SDK understands.

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        pushEventHandler.onPushAction(UNNotificationResponseWrapper(response: response), completionHandler: completionHandler)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        pushEventHandler.shouldDisplayPushAppInForeground(UNNotificationWrapper(notification: notification)) { shouldShowPush in
            if shouldShowPush {
                if #available(iOS 14.0, *) {
                    completionHandler([.list, .banner, .badge, .sound])
                } else {
                    completionHandler([.badge, .sound])
                }
            } else {
                completionHandler([])
            }
        }
    }

    // Swizzle method convenient when original and swizzled methods both belong to same class.
    func swizzle(forClass: AnyClass, original: Selector, new: Selector) {
        guard let originalMethod = class_getInstanceMethod(forClass, original) else { return }
        guard let swizzledMethod = class_getInstanceMethod(forClass, new) else { return }

        let didAddMethod = class_addMethod(forClass, original, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))

        if didAddMethod {
            class_replaceMethod(forClass, new, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod))
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }
}

// This is a bit confusing and makes the code a little more complex. However, it's the most reliable way found to get UNUserNotificationCenter.delegate swizzling to work by using an extension.
@available(iOSApplicationExtension, unavailable)
extension UNUserNotificationCenter {
    // Swizzled method that gets called when `UNUserNotificationCenter.current().delegate` setter called.
    @objc dynamic func cio_swizzled_setDelegate(delegate: UNUserNotificationCenterDelegate?) {
        let logger = DIGraphShared.shared.logger
        let userNotificationsFrameworkAdapter = DIGraphShared.shared.userNotificationsFrameworkAdapter

        logger.debug("New UNUserNotificationCenter.delegate set. Delegate class: \(String(describing: delegate))")

        userNotificationsFrameworkAdapter.newNotificationCenterDelegateSet(delegate)

        // Forward request to the original implementation that we swizzled. So that the app finishes setting UNUserNotificationCenter.delegate.
        //
        // Instead of providing the given 'delegate', provide CIO SDK's click handler.
        // This will force our SDK to be the 1 push click handler of the app instead of the given 'delegate'.
        cio_swizzled_setDelegate(delegate: userNotificationsFrameworkAdapter.delegate)
    }
}
