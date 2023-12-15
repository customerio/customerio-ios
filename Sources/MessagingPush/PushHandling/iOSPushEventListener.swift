import CioInternalCommon
import CioTracking
import Foundation
import UserNotifications

protocol PushEventListener: AutoMockable {
    var delegate: UNUserNotificationCenterDelegate { get }
    func newNotificationCenterDelegateSet(_ newDelegate: UNUserNotificationCenterDelegate?)
    func beginListening()
}

@available(iOSApplicationExtension, unavailable)
// Singleton because:
// 1. class stores data that needs to be kept in-memory.
//
// sourcery: InjectRegister = "PushEventListener"
// sourcery: InjectSingleton
class IOSPushEventListener: NSObject, PushEventListener, UNUserNotificationCenterDelegate {
    private var userNotificationCenter: UserNotificationCenter
    private let jsonAdapter: JsonAdapter
    private var moduleConfig: MessagingPushConfigOptions
    private let pushClickHandler: PushClickHandler
    private let pushHistory: PushHistory

    // Make sure that this proxy is held in-memory.
    private let notificationCenterDelegateProxy = NotificationCenterDelegateProxy()

    init(userNotificationCenter: UserNotificationCenter, jsonAdapter: JsonAdapter, moduleConfig: MessagingPushConfigOptions, pushClickHandler: PushClickHandler, pushHistory: PushHistory) {
        self.userNotificationCenter = userNotificationCenter
        self.jsonAdapter = jsonAdapter
        self.moduleConfig = moduleConfig
        self.pushClickHandler = pushClickHandler
        self.pushHistory = pushHistory
    }

    var delegate: UNUserNotificationCenterDelegate {
        self
    }

    func beginListening() {
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
        notificationCenterDelegateProxy.newNotificationCenterDelegateSet(newDelegate)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        guard !pushHistory.hasHandledPushDidReceive(pushId: response.pushId) else {
            // push has already been handled. exit early
            // Prevents infinite loops if our NotificationCenter delegate calls other delegates via proxy and then those nested delegates calls our delegate again.
            return
        }
        pushHistory.didHandlePushDidReceive(pushId: response.pushId)

        guard let parsedPush = CustomerIOParsedPushPayload.parse(response: response, jsonAdapter: jsonAdapter) else {
            // push did not come from CIO
            // Do not call completionHandler() because push did not come from CIO.
            // Forward the request to all other push click handlers in app to give them a chance to handle it.
            notificationCenterDelegateProxy.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)

            return
        }

        if response.didClickOnPush {
            pushClickHandler.pushClicked(parsedPush)
        }

        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        guard !pushHistory.hasHandledPushWillPresent(pushId: notification.pushId) else {
            // push has already been handled. exit early
            // Prevents infinite loops if our NotificationCenter delegate calls other delegates via proxy and then those nested delegates calls our delegate again.
            return
        }
        pushHistory.didHandlePushWillPresent(pushId: notification.pushId)

        guard let _ = CustomerIOParsedPushPayload.parse(notificationContent: notification.request.content, jsonAdapter: jsonAdapter) else {
            // push did not come from CIO
            // Do not call completionHandler() because push did not come from CIO.
            // Forward the request to all other push click handlers in app to give them a chance to handle it.
            notificationCenterDelegateProxy.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)

            return
        }

        // Push came from CIO. Handle the push on behalf of the customer.
        // Make sure to call completionHandler() so the customer does not need to.

        if moduleConfig.showPushAppInForeground {
            // Tell the OS to show the push while app in foreground using 1 of the below options, depending on version of OS
            if #available(iOS 14.0, *) {
                completionHandler([.list, .banner, .badge, .sound])
            } else {
                completionHandler([.badge, .sound])
            }
        } else {
            completionHandler([]) // do not show push while app in foreground
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
        guard let diGraph = SdkInitializedUtilImpl().postInitializedData?.diGraph else {
            // SDK not initialized yet. We hope that this function never gets called because auto push click handling will not work if this function called.

            // Forward request to the original implementation implementation that we swizzled. So that the app finishes setting UNUserNotificationCenter.delegate.
            // We have to provide the original delegate object because the SDK has not yet been initialized.
            cio_swizzled_setDelegate(delegate: delegate)

            return
        }

        diGraph.logger.debug("New UNUserNotificationCenter.delegate set. Delegate class: \(String(describing: delegate))")

        diGraph.pushEventListener.newNotificationCenterDelegateSet(delegate)

        // Forward request to the original implementation that we swizzled. So that the app finishes setting UNUserNotificationCenter.delegate.
        //
        // Instead of providing the given 'delegate', provide CIO SDK's click handler.
        // This will force our SDK to be the 1 push click handler of the app instead of the given 'delegate'.
        cio_swizzled_setDelegate(delegate: diGraph.pushEventListener.delegate)
    }
}
