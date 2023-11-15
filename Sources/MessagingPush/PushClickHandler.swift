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

    private var customerIO: CustomerIO? {
        sdkInitializedUtil.customerio
    }

    init(jsonAdapter: JsonAdapter, sdkConfig: SdkConfig, deepLinkUtil: DeepLinkUtil, userNotificationCenter: UserNotificationCenter) {
        self.jsonAdapter = jsonAdapter
        self.sdkConfig = sdkConfig
        self.deepLinkUtil = deepLinkUtil
        self.userNotificationCenter = userNotificationCenter
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
            myClass: PushClickHandlerImpl.self,
            mySelector: #selector(PushClickHandlerImpl.cio_swizzled_setDelegate(delegate:))
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

    func setupClickHandling(onDelegate delegate: UNUserNotificationCenterDelegate) {
        // Only swizzle on delegates that are not part of the CIO SDK.
        // Problems such as infinite loops when a push is clicked can occur if the CIO SDK is setup as the app's click handler *and*
        // we setup swizzling on our own delegate.
        if delegate is PushClickHandlerImpl {
            return
        }

        // Another SDK or the host app has set itself as the new UNUserNotificationCenter.delegate. We want to make sure the CIO SDK
        // can still handle push clicks to make integration of the CIO SDK easy and reliable. We use swizzling on the new delegate instance
        // so our SDK still gets notified when a push is clicked, even though the new delegate is setup to handle the push click.
        swizzle(
            targetClass: type(of: delegate),
            targetSelector: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)),
            myClass: PushClickHandlerImpl.self,
            mySelector: #selector(PushClickHandlerImpl.cio_swizzle_didReceive(_:didReceive:withCompletionHandler:))
        )
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) -> CustomerIOParsedPushPayload? {
        guard let parsedPush = CustomerIOParsedPushPayload.parse(response: response, jsonAdapter: jsonAdapter) else {
            // push not sent from CIO. exit early
            return nil
        }

        if response.didClickOnPush {
            pushClicked(response, parsedPush: parsedPush)
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
            pushClicked(response, parsedPush: parsedPush)
        }

        completionHandler()
        return true
    }

    private func pushClicked(_ response: UNNotificationResponse, parsedPush: CustomerIOParsedPushPayload) {
        // TODO: prevent duplicate push metrics and deep link handling.

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
extension PushClickHandlerImpl {
    // Swizzled method that gets called when a new UNUserNotificationCenter.delegate gets set.
    @objc dynamic func cio_swizzled_setDelegate(delegate: UNUserNotificationCenterDelegate?) {
        guard let delegate = delegate else {
            cio_swizzled_setDelegate(delegate: delegate) // continue swizzle
            return
        }

        setupClickHandling(onDelegate: delegate)

        cio_swizzled_setDelegate(delegate: delegate) // continue swizzle
    }

    // Swizzled method that gets called when a push notification gets clicked or swiped away
    @objc dynamic func cio_swizzle_didReceive(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        _ = userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)

        // continue swizzle
        cio_swizzle_didReceive(center, didReceive: response, withCompletionHandler: completionHandler)
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
