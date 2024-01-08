import CioInternalCommon
import CioTracking
import Foundation
import UserNotifications

protocol PushEventListener: AutoMockable {
    // Called when a push notification was acted upon. Either clicked or swiped away.
    //
    // return true if push was handled by this SDK. Meaning, the push notification was sent by CIO.
    func onPushAction(_ push: PushNotification, didClickOnPush: Bool) -> Bool
    // return nil if the push was not handled by CIO SDK.
    // return true if should diplay the push in foreground.
    func shouldDisplayPushAppInForeground(_ push: PushNotification) -> Bool?
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
class iOSPushEventListener: PushEventListener {
    // Singleton instance of this class maintained outside of the digraph.
    public static let shared = iOSPushEventListener()

    // Instances of all dependencies that automated tests can override.
    private var overrideJsonAdapter: JsonAdapter?
    private var overrideModuleConfig: MessagingPushConfigOptions?
    private var overridePushClickHandler: PushClickHandler?
    private var overridePushHistory: PushHistory?

    // Below is a set of getters for all dependencies of this class.
    // Each getter will first check if a test override exists. If so, return that. Otherwise, return an instance from the digraph.
    // It's important that we use do not keep a strong reference to any dependencies or to the digraph. Otherwise, the SDK would crash if the SDK's digraph gets re-initialized and
    // this class tries to access old instances of dependencies.
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

    // Init for testing. Injecting mocks.
    init(jsonAdapter: JsonAdapter, moduleConfig: MessagingPushConfigOptions, pushClickHandler: PushClickHandler, pushHistory: PushHistory) {
        self.overrideJsonAdapter = jsonAdapter
        self.overrideModuleConfig = moduleConfig
        self.overridePushClickHandler = pushClickHandler
        self.overridePushHistory = pushHistory
    }

    // singleton constructor
    private init() {}

    func onPushAction(_ push: PushNotification, didClickOnPush: Bool) -> Bool {
        guard let pushClickHandler = pushClickHandler,
              let pushHistory = pushHistory,
              let jsonAdapter = jsonAdapter
        else {
            return false
        }
        logger?.debug("On push action event. push: \(push))")

        guard !pushHistory.hasHandledPush(pushEvent: .didReceive, pushId: push.pushId, pushDeliveryDate: push.deliveryDate) else {
            // push has already been handled. exit early
            return true
        }

        guard let parsedPush = CustomerIOParsedPushPayload.parse(pushNotification: push, jsonAdapter: jsonAdapter) else {
            // push did not come from CIO
            // Do not call completionHandler() because push did not come from CIO.
            // Forward the request to all other push click handlers in app to give them a chance to handle it.

            // TODO: move proxy call to NotificationCenterFrameworkAdapterImpl since it's what has knowledge about parameters required to call proxy.
//            notificationCenterDelegateProxy.pushClicked(push, completionHandler: completionHandler)

            return false
        }

        logger?.debug("Push came from CIO. Handle the didReceive event on behalf of the customer.")

        if didClickOnPush {
            pushClickHandler.pushClicked(parsedPush)
        }

        return true
    }

    func shouldDisplayPushAppInForeground(_ push: PushNotification) -> Bool? {
        guard let pushHistory = pushHistory,
              let jsonAdapter = jsonAdapter,
              let moduleConfig = moduleConfig
        else {
            return nil
        }
        logger?.debug("Push event: willPresent. push: \(push)")

        guard !pushHistory.hasHandledPush(pushEvent: .willPresent, pushId: push.pushId, pushDeliveryDate: push.deliveryDate) else {
            // push has already been handled. exit early

            // See notes in didReceive function to learn more about this logic of exiting early when we already have handled a push.
            return nil
        }

        guard let _ = CustomerIOParsedPushPayload.parse(pushNotification: push, jsonAdapter: jsonAdapter) else {
            // push did not come from CIO
            // Do not call completionHandler() because push did not come from CIO.
            // Forward the request to all other push click handlers in app to give them a chance to handle it.

            // TODO: move proxy call to NotificationCenterFrameworkAdapterImpl since it's what has knowledge about parameters required to call proxy.
//             notificationCenterDelegateProxy.shouldDisplayPushAppInForeground(push, completionHandler: completionHandler)

            return nil
        }

        logger?.debug("Push came from CIO. Handle the willPresent event on behalf of the customer.")

        return moduleConfig.showPushAppInForeground
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
