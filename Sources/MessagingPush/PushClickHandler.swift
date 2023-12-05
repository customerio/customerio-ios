import CioInternalCommon
import CioTracking
import Foundation
import UserNotifications

protocol PushClickHandler: AutoMockable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) -> CustomerIOParsedPushPayload?

    // sourcery:Name=userNotificationCenterWithCompletionHandler
    // sourcery:DuplicateMethod=userNotificationCenter
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) -> Bool

    func setupClickHandling()

    func didSetDelegate(_ delegate: UNUserNotificationCenterDelegate?)
}

@available(iOSApplicationExtension, unavailable)
// Make class a singleton to avoid being garbage collected. A strong reference needs to be held of instance.
// We are setting this class to be UNUserNotificationCenter.delegate instance and delegates are usually weak.
//
// sourcery: InjectRegister = "PushClickHandler"
// sourcery: InjectSingleton
class PushClickHandlerImpl: NSObject, PushClickHandler, UNUserNotificationCenterDelegate {
    private let jsonAdapter: JsonAdapter
    private let sdkConfig: SdkConfig
    private let sdkInitializedUtil: SdkInitializedUtil
    private let deepLinkUtil: DeepLinkUtil
    private var userNotificationCenter: UserNotificationCenter
    private let pushHistory: PushHistory

    private var messagingPushConfig: MessagingPushConfigOptions

    // Use a map so that we only save 1 instance of a given Delegate.
    private var nestedDelegates: [String: UNUserNotificationCenterDelegate] = [:]

    private var customerIO: CustomerIO? {
        sdkInitializedUtil.customerio
    }

    init(jsonAdapter: JsonAdapter, sdkConfig: SdkConfig, deepLinkUtil: DeepLinkUtil, userNotificationCenter: UserNotificationCenter, pushHistory: PushHistory, messagingPushConfig: MessagingPushConfigOptions) {
        self.jsonAdapter = jsonAdapter
        self.sdkConfig = sdkConfig
        self.deepLinkUtil = deepLinkUtil
        self.userNotificationCenter = userNotificationCenter
        self.pushHistory = pushHistory
        self.messagingPushConfig = messagingPushConfig
        self.sdkInitializedUtil = SdkInitializedUtilImpl()
    }

    func setupClickHandling() {
        // UNUserNotificationCenter.delegate is the 1 object in an iOS app that gets called when a push is clicked.
        // We can set the CIO SDK as the delegate, but another SDK or the host app can set itself as the delegate instead which
        // cause the CIO SDK to not be able to automatically handle pushes. To get around this we use swizzling to get notified when
        // a new delegate gets set after we set the CIO SDK as the delegate. Therefore, we know when someone else takes over the
        // click handling in the app.
        swizzle(
            forClass: UNUserNotificationCenter.self,
            original: #selector(setter: UNUserNotificationCenter.delegate),
            new: #selector(UNUserNotificationCenter.cio_swizzled_setDelegate(delegate:))
        )

        // This re-assignment triggers NotifiationCenter.delegate setter that we swizzled so our SDK can swizzle in its logic.
        userNotificationCenter.currentDelegate = userNotificationCenter.currentDelegate
    }

    func didSetDelegate(_ delegate: UNUserNotificationCenterDelegate?) {
        if let delegate = delegate {
            let doesDelegateBelongToCio = delegate is PushClickHandlerImpl
            if !doesDelegateBelongToCio {
                let nestedDelegateKey = String(describing: delegate)
                nestedDelegates[nestedDelegateKey] = delegate
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let _: Bool = userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        guard let parsedPush = CustomerIOParsedPushPayload.parse(notificationContent: notification.request.content, jsonAdapter: jsonAdapter) else {
            // push did not come from CIO
            // Do not call completionHandler() because push did not come from CIO.
            // Forward the request to all other push click handlers in app to give them a chance to handle it.
            nestedDelegates.forEach {
                // userNotificationCenter(_:willPresent:withCompletionHandler:) is optional
                // so we use optional chaining to call it if it exists
                $0.value.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: completionHandler)
            }

            return
        }

        // Push came from CIO. Handle the push on behalf of the customer.
        // Make sure to call completionHandler() so the customer does not need to.

        if messagingPushConfig.showPushAppInForeground {
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

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) -> CustomerIOParsedPushPayload? {
        guard let parsedPush = CustomerIOParsedPushPayload.parse(response: response, jsonAdapter: jsonAdapter) else {
            // push not sent from CIO. exit early
            return nil
        }

        if response.didClickOnPush {
            pushClicked(parsedPush)
        }

        return parsedPush
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) -> Bool {
        guard let parsedPush = CustomerIOParsedPushPayload.parse(response: response, jsonAdapter: jsonAdapter) else {
            // push did not come from CIO
            // Do not call completionHandler() because push did not come from CIO.
            // Forward the request to all other push click handlers in app to give them a chance to handle it.
            nestedDelegates.forEach {
                // userNotificationCenter(_:didReceive:withCompletionHandler:) is optional
                // so we use optional chaining to call it if it exists
                $0.value.userNotificationCenter?(center, didReceive: response, withCompletionHandler: completionHandler)
            }

            return false
        }

        if response.didClickOnPush {
            pushClicked(parsedPush)
        }

        completionHandler()
        return true
    }

    private func pushClicked(_ parsedPush: CustomerIOParsedPushPayload) {
        guard !pushHistory.hasHandledPushClick(deliveryId: parsedPush.deliveryId) else {
            // push has already been handled. exit early
            return
        }
        pushHistory.handledPushClick(deliveryId: parsedPush.deliveryId)

        // Now we are ready to handle the push click.
        // Track metrics
        if sdkConfig.autoTrackPushEvents {
            customerIO?.trackMetric(deliveryID: parsedPush.deliveryId, event: .opened, deviceToken: parsedPush.deviceToken)
        }

        // Cleanup files on device that were used when the push was displayed. Files are no longer
        // needed now that the push is no longer shown.
        cleanupAfterPushInteractedWith(pushContent: parsedPush)

        // Handle deep link, if there is one attached to push.
        if let deepLinkUrl = parsedPush.deepLink {
            deepLinkUtil.handleDeepLink(deepLinkUrl)
        }
    }

    // There are files that are created just for displaying a rich push. After a push is interacted with, those files
    // are no longer needed.
    // This function's job is to cleanup after a push is no longer being displayed.
    func cleanupAfterPushInteractedWith(pushContent: CustomerIOParsedPushPayload) {
        pushContent.cioAttachments.forEach { attachment in
            let localFilePath = attachment.url

            try? FileManager.default.removeItem(at: localFilePath)
        }
    }
}

@available(iOSApplicationExtension, unavailable)
// Swizzle functions
// I have found best success with swizzling when the swizzled functions are extensions added to the class
// that we are trying to swizzle. Memory access errors have been thrown when when a swizzled method is trying
// to access variables inside of a class. By using extensions and having swizzled functions make calls to the
// SDK via static function calls, we can avoid those issues.
extension UNUserNotificationCenter {
    // Swizzled method that gets called when a new UNUserNotificationCenter.delegate gets set.
    @objc dynamic func cio_swizzled_setDelegate(delegate: UNUserNotificationCenterDelegate?) {
        guard let pushClickHandler = SdkInitializedUtilImpl().postInitializedData?.diGraph.pushClickHandler else {
            // SDK not yet initialized. Exit early.

            // Forward request to the original implementation that we swizzled.
            // Provide the given 'delegate' as CIO SDK's click handler not available until SDK initialized.
            cio_swizzled_setDelegate(delegate: delegate)

            return
        }

        // Save the delegate to call it later
        pushClickHandler.didSetDelegate(delegate)

        // Forward request to the original implementation that we swizzled.
        // Instead of providing the given 'delegate', provide CIO SDK's click handler.
        // This will force our SDK to be the 1 push click handler of the app instead of the given 'delegate'.
        cio_swizzled_setDelegate(delegate: pushClickHandler as! UNUserNotificationCenterDelegate)
    }
}

// TODO: cleanup duplicate swizzle functions all over codebase.

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
