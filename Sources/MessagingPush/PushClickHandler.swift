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
            targetClass: UNUserNotificationCenter.self,
            targetSelector: #selector(setter: UNUserNotificationCenter.delegate),
            myClass: UNUserNotificationCenter.self,
            mySelector: #selector(UNUserNotificationCenter.cio_swizzled_setDelegate(delegate:))
        )

        if userNotificationCenter.currentDelegate == nil {
            // Set our SDK as the click handler, if there isn't one already set in the app.
            userNotificationCenter.currentDelegate = self
        } else {
            // This handles the case where a delegate may have already been assigned before our SDK is loaded into memory.
            // This re-assignment triggers NotifiationCenter.delegate setter that we swizzled so our SDK can swizzle in its logic.
            userNotificationCenter.currentDelegate = userNotificationCenter.currentDelegate
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
            // Do not call completionHandler() because push did not come from CIO. Another service might have sent it so
            // allow another SDK
            // to call the completionHandler()
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
        if let delegate = delegate {
            let doesDelegateBelongToCio = delegate is PushClickHandlerImpl

            // An infinite loop can occur if we handle push click in SDK's delegate *and* handle push click via swizzling. Skip swizzling if delete is SDK's delegate.
            if !doesDelegateBelongToCio {
                // Another SDK or the host app has set itself as the new UNUserNotificationCenter.delegate. We want to make sure the CIO SDK
                // can still handle push clicks to make integration of the CIO SDK easy and reliable. We use swizzling on the new delegate instance
                // so our SDK still gets notified when a push is clicked, even though the new delegate is setup to handle the push click.
                swizzle(
                    targetClass: type(of: delegate),
                    targetSelector: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)),
                    myClass: UNUserNotificationCenter.self,
                    mySelector: #selector(UNUserNotificationCenter.cio_swizzle_didReceive(_:didReceive:withCompletionHandler:))
                )
            }
        }

        cio_swizzled_setDelegate(delegate: delegate) // continue swizzle
    }

    // Swizzled method that gets called when a push notification gets clicked or swiped away
    @objc dynamic func cio_swizzle_didReceive(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        _ = MessagingPush.shared.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)

        // continue swizzle
        cio_swizzle_didReceive(center, didReceive: response, withCompletionHandler: completionHandler)
    }

    // Swizzled method that gets called before the OS displays the push. Used to determine if a push gets displayed while app is in foreground or not.
    @objc dynamic func cio_swizzle_willPresent(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        guard let _ = CustomerIOParsedPushPayload.parse(notificationContent: notification.request.content, jsonAdapter: jsonAdapter) else {
            // push not sent from CIO. exit early and ignore request
            return
        }

        if messagingPushConfig.showPushAppInForeground {
            if #available(iOS 14.0, *) {
                completionHandler([.list, .banner, .badge, .sound])
            } else {
                completionHandler([.badge, .sound])
            }
        }

        // continue swizzle
        cio_swizzle_willPresent(center, willPresent: notification, withCompletionHandler: completionHandler)
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

// Swizzle method convenient when swizzled method is in a different class then the original method.
func swizzle(targetClass: AnyClass, targetSelector: Selector, myClass: AnyClass, mySelector: Selector) {
    guard let newMethod = class_getInstanceMethod(myClass, mySelector) else {
        return
    }
    let newImplementation = method_getImplementation(newMethod)

    let methodTypeEncoding = method_getTypeEncoding(newMethod)

    let existingMethod = class_getInstanceMethod(targetClass, targetSelector)
    if existingMethod != nil {
        guard let originalMethod = class_getInstanceMethod(targetClass, targetSelector) else {
            return
        }
        let originalImplementation = method_getImplementation(originalMethod)

        guard newImplementation != originalImplementation else {
            return
        }

        class_addMethod(targetClass, mySelector, newImplementation, methodTypeEncoding)
        let newMethod = class_getInstanceMethod(targetClass, mySelector)
        method_exchangeImplementations(originalMethod, newMethod!)
    } else {
        class_addMethod(targetClass, targetSelector, newImplementation, methodTypeEncoding)
    }
}
