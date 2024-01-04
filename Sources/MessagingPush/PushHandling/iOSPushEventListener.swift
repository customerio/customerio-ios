import CioInternalCommon
import CioTracking
import Foundation
import UserNotifications

protocol PushEventListener {
    func onPushClicked(_ push: PushNotification, completionHandler: @escaping () -> Void)
    func shouldDisplayPushAppInForeground(_ push: PushNotification, completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
}

@available(iOSApplicationExtension, unavailable)
/**

 # Why is this class a singleton?
 1. Class stores data that needs to be kept in-memory.

 ---

 # Why is this class not stored in the digraph?

 This class is the SDK's `UNUserNotificationCenterDelegate` instance.  Meaning, the CIO SDK registers this class with the OS in order to
 receive callbacks when push notifications are interacted with.

 It's important that the instance of this class provided to the OS stays in memory so our SDK can receive those OS callbacks.

 In order to promise this class's singleton instance stays in memory, the singleton instance is *not* stored inside of the digraph (like all other singletons in our SDK is).

 This is a workaound to prevent this scenario:
 - native iOS SDK is initialized.
 - PushEventListener singleton instance is created.
 - PushEventListener singleton instance is registered with the OS to receive push notification callbacks.
 - SDK wrappers re-initialize the native iOS SDK when the SDK wrapper SDK is initialized.
 - During the native iOS SDK's initialization, the SDK's digraph instance is re-created. All objects (and singletons) in that old digraph instance are deleted from memory.
 - That's bad! If the PushEventListener singleton instance was stored in the digraph, it would be deleted from memory. The OS would no longer be able to send push notification callbacks to the SDK.
 */
class iOSPushEventListener: BaseSdkPushEventListener {
    // Singleton instance of this class maintained outside of the digraph.
    public static let shared = iOSPushEventListener()

    // Instances of all dependencies that automated tests can override.
    private var overrideUserNotificationCenter: UserNotificationCenter?
    private var overrideJsonAdapter: JsonAdapter?
    private var overrideModuleConfig: MessagingPushConfigOptions?
    private var overridePushClickHandler: PushClickHandler?
    private var overridePushHistory: PushHistory?

    // Below is a set of getters for all dependencies of this class.
    // Each getter will first check if a test override exists. If so, return that. Otherwise, return an instance from the digraph.
    // It's important that we use do not keep a strong reference to any dependencies or to the digraph. Otherwise, the SDK would crash if the SDK's digraph gets re-initialized and
    // this class tries to access old instances of dependencies.
    private var userNotificationCenter: UserNotificationCenter? {
        overrideUserNotificationCenter ?? diGraph?.userNotificationCenter
    }

    private var jsonAdapter: JsonAdapter? {
        overrideJsonAdapter ?? diGraph?.jsonAdapter
    }

    private var moduleConfig: MessagingPushConfigOptions? {
        overrideModuleConfig ?? diGraph?.messagingPushConfigOptions
    }

    private var pushClickHandler: PushClickHandler? {
        overridePushClickHandler ?? diGraph?.pushClickHandler
    }

    private var pushHistory: PushHistory? {
        overridePushHistory ?? diGraph?.pushHistory
    }

    private var logger: Logger? {
        diGraph?.logger
    }

    // Convenient getter of the digraph for dependency getters above.
    private var diGraph: DIGraph? {
        SdkInitializedUtilImpl().postInitializedData?.diGraph
    }

    // Make sure that this proxy is held in-memory while the SDK is in memory.
    private let notificationCenterDelegateProxy = NotificationCenterDelegateProxy()

    // Init for testing. Injecting mocks.
    init(userNotificationCenter: UserNotificationCenter, jsonAdapter: JsonAdapter, moduleConfig: MessagingPushConfigOptions, pushClickHandler: PushClickHandler, pushHistory: PushHistory) {
        self.overrideUserNotificationCenter = userNotificationCenter
        self.overrideJsonAdapter = jsonAdapter
        self.overrideModuleConfig = moduleConfig
        self.overridePushClickHandler = pushClickHandler
        self.overridePushHistory = pushHistory
    }

    // singleton init
    override init() {}

    func beginListening() {
        guard var userNotificationCenter = userNotificationCenter else {
            return
        }

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

    override func onPushClicked(_ push: PushNotification, completionHandler: @escaping () -> Void) {
        guard let pushClickHandler = pushClickHandler,
              let pushHistory = pushHistory,
              let jsonAdapter = jsonAdapter
        else {
            return
        }
        logger?.debug("Push event: didReceive. push: \(push))")

        guard !pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: push.pushId, pushDeliveryDate: push.deliveryDate) else {
            // push has already been handled. exit early
            return
        }

        guard let parsedPush = CustomerIOParsedPushPayload.parse(response: response, jsonAdapter: jsonAdapter) else {
            // push did not come from CIO
            // Do not call completionHandler() because push did not come from CIO.
            // Forward the request to all other push click handlers in app to give them a chance to handle it.
            notificationCenterDelegateProxy.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)

            return
        }

        logger?.debug("Push came from CIO. Handle the didReceive event on behalf of the customer.")

        if response.didClickOnPush {
            pushClickHandler.pushClicked(parsedPush)
        }

        completionHandler()
    }

    override func shouldDisplayPushAppInForeground(_ push: PushNotification, completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        guard let pushHistory = pushHistory,
              let jsonAdapter = jsonAdapter,
              let moduleConfig = moduleConfig
        else {
            return
        }
        logger?.debug("Push event: willPresent. push: \(notification)")

        guard !pushHistory.hasHandledPush(pushEvent: .willPresent, pushId: notification.pushId, pushDeliveryDate: notification.date) else {
            // push has already been handled. exit early

            // See notes in didReceive function to learn more about this logic of exiting early when we already have handled a push.
            return
        }

        guard let _ = CustomerIOParsedPushPayload.parse(notificationContent: notification.request.content, jsonAdapter: jsonAdapter) else {
            // push did not come from CIO
            // Do not call completionHandler() because push did not come from CIO.
            // Forward the request to all other push click handlers in app to give them a chance to handle it.
            notificationCenterDelegateProxy.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)

            return
        }

        logger?.debug("Push came from CIO. Handle the willPresent event on behalf of the customer.")

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

// Manually add a getter for the PushEventListener in the digraph.
// We must use this manual approach instead of auto generated code because the PushEventListener maintains its own singleton instance outside of the digraph.
// This getter is allows other classes to use the digraph to get the singleton instance of the PushEventListener, if needed.
extension DIGraph {
    @available(iOSApplicationExtension, unavailable)
    var pushEventListener: PushEventListener {
        iOSPushEventListener.shared
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
