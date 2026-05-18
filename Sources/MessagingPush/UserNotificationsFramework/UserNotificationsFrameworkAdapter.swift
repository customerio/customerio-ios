import CioInternalCommon
import Foundation
import UserNotifications

/**
 The iOS framework, `UserNotifications`, is abstracted away from the SDK codebase.

 This file is the connection between our SDK and `UserNotifications`.
 In production, iOS will call functions in this file. Those requests are then forwarded onto the abstracted code in the SDK to perform all of the logic.
 */
@available(iOSApplicationExtension, unavailable)
@available(*, deprecated, message: "This swizzling based system is replaced with CioAppDelegate(Wrapper)")
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
@available(*, deprecated, message: "This swizzling based system is replaced with CioAppDelegate(Wrapper)")
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
