import CioTracking
import Foundation
import UserNotifications

/**
 The push features in the SDK interact with the iOS framework, `UserNotifications`.
 In order for us to write automated tests around our code that interacts with this framework, we treat `UserNotifications` as a dependency and mock it.

 This file is part of that by being the adapter between our SDK and the iOS framework.
 */

protocol NotificationCenterFrameworkAdapter {
    // A strongly typed reference to an instance of UNUserNotificationCenterDelegate that we can provide to iOS in producdtion.
    var delegate: UNUserNotificationCenterDelegate { get }

    func beginListeningNewNotificationCenterDelegateSet()
    func newNotificationCenterDelegateSet(_ newDelegate: UNUserNotificationCenterDelegate?)
}

/**
 This class is an adapter that makes our SDK communicate with the iOS framework, `UserNotifications` in production.

 This allows our SDK to not have knowledge of the `UserNotifications` framework, which makes it easier to write automated tests around our SDK.

 Keep this class simple because it is only able to be tested in QA testing. It's meant to be an adapter, not contain logic.
 */
// sourcery: InjectRegister = "NotificationCenterFrameworkAdapter"
class NotificationCenterFrameworkAdapterImpl: NSObject, UNUserNotificationCenterDelegate, NotificationCenterFrameworkAdapter {
    private let pushEventHandler: PushEventHandler
    private var userNotificationCenter: UserNotificationCenter

    private var notificationCenterDelegateProxy: NotificationCenterDelegateProxy {
        NotificationCenterDelegateProxyImpl.shared
    }

    init(pushEventHandler: PushEventHandler, userNotificationCenter: UserNotificationCenter) {
        self.pushEventHandler = pushEventHandler
        self.userNotificationCenter = userNotificationCenter
    }

    var delegate: UNUserNotificationCenterDelegate {
        self
    }

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

    // Functions called by iOS framework, `UserNotifications`. This adapter class simply passes these requests to other code in our SDK where the logic exists.

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        pushEventHandler.onPushAction(UNNotificationResponseWrapper(response: response), completionHandler: completionHandler)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        pushEventHandler.shouldDisplayPushAppInForeground(UNNotificationWrapper(notification: notification), completionHandler: completionHandler)
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
        guard let diGraph = SdkInitializedUtilImpl().postInitializedData?.diGraph else {
            // SDK not initialized yet. We hope that this function never gets called because auto push click handling will not work if this function called.

            // Forward request to the original implementation implementation that we swizzled. So that the app finishes setting UNUserNotificationCenter.delegate.
            // We have to provide the original delegate object because the SDK has not yet been initialized.
            cio_swizzled_setDelegate(delegate: delegate)

            return
        }

        diGraph.logger.debug("New UNUserNotificationCenter.delegate set. Delegate class: \(String(describing: delegate))")

        diGraph.notificationCenterFrameworkAdapter.newNotificationCenterDelegateSet(delegate)

        // Forward request to the original implementation that we swizzled. So that the app finishes setting UNUserNotificationCenter.delegate.
        //
        // Instead of providing the given 'delegate', provide CIO SDK's click handler.
        // This will force our SDK to be the 1 push click handler of the app instead of the given 'delegate'.
        cio_swizzled_setDelegate(delegate: diGraph.notificationCenterFrameworkAdapter.delegate)
    }
}

// A class that represents a push notification received by the iOS framework, `UserNotifications`.
// When our SDK receives a push notification from the `UserNotification` framework, the push is converted into
// an instance of this class, first.
//
// This allows us to write automated tests around our SDK's push handling logic because classes inside of `UserUnotifications` internal and not mockable.
public protocol PushNotification {
    var pushId: String { get }
    var deliveryDate: Date { get }
    var title: String { get }
    var message: String { get }
    var data: [AnyHashable: Any] { get }
}

// Represents UNNotificationResponse instance.
public protocol PushNotificationAction {
    var push: PushNotification { get }
    var didClickOnPush: Bool { get }
}

// Conforms UNNotificationResponse to the PushNotification protocol.
class UNNotificationResponseWrapper: PushNotificationAction {
    public let response: UNNotificationResponse

    var push: PushNotification {
        UNNotificationWrapper(notification: response.notification)
    }

    var didClickOnPush: Bool {
        response.didClickOnPush
    }

    init(response: UNNotificationResponse) {
        self.response = response
    }
}

// Conforms UNNotification to the PushNotification protocol.
class UNNotificationWrapper: PushNotification {
    public let notification: UNNotification

    var pushId: String {
        notification.request.identifier
    }

    var deliveryDate: Date {
        notification.date
    }

    var title: String {
        notification.request.content.title
    }

    var message: String {
        notification.request.content.body
    }

    var data: [AnyHashable: Any] {
        notification.request.content.userInfo
    }

    init(notification: UNNotification) {
        self.notification = notification
    }
}

// Represents `UNUserNotificationCenterDelegate` in the iOS framework, `UserNotifications`.
// We do this because classes in `UserNotifications` framework is not testable.
protocol PushEventHandler {
    // Called when a push notification was acted upon. Either clicked or swiped away.
    // Replacement of: `userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void)`
    func onPushAction(_ pushAction: PushNotificationAction, completionHandler: @escaping () -> Void)
    // Called when a push is received and the app is in the foreground. iOS asks the host app if the push should be shown, or not.
    // Replacement of: `userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)`
    func shouldDisplayPushAppInForeground(_ push: PushNotification, completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
}

// Makes `UNUserNotificationCenterDelegate` conform to `PushEventHandler`.
// This allows our SDK to call UserNotification.UNUserNotificationCenterDelegate instances in production, even though our SDK has abstracted the framework away.
class UNUserNotificationCenterDelegateWrapper: PushEventHandler {
    private let delegate: UNUserNotificationCenterDelegate

    init(delegate: UNUserNotificationCenterDelegate) {
        self.delegate = delegate
    }

    func onPushAction(_ pushAction: PushNotificationAction, completionHandler: @escaping () -> Void) {
        guard let userNotificationsWrapperInstance = pushAction as? UNNotificationResponseWrapper else {
            return
        }

        delegate.userNotificationCenter?(UNUserNotificationCenter.current(), didReceive: userNotificationsWrapperInstance.response, withCompletionHandler: completionHandler)
    }

    func shouldDisplayPushAppInForeground(_ push: PushNotification, completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        guard let unnotification = push as? UNNotificationWrapper else {
            return
        }

        delegate.userNotificationCenter?(UNUserNotificationCenter.current(), willPresent: unnotification.notification, withCompletionHandler: completionHandler)
    }
}
