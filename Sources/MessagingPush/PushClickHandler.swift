import CioInternalCommon
import Foundation
import UserNotifications

protocol PushClickHandler: AutoMockable {
    func setupClickHandling()
}

// Setup class to become a singleton to avoid instance being garbage collected. A strong reference needs to be held of instance.
// We are setting this class to be UNUserNotificationCenter.delegate instance and delegates are usually weak.
//
// sourcery: InjectRegister = "PushClickHandler"
// sourcery: InjectSingleton
class PushClickHandlerImpl: NSObject, PushClickHandler, UNUserNotificationCenterDelegate {
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

        if UNUserNotificationCenter.current().delegate == nil {
            // Set our SDK as the click handler, if there isn't one already set in the app.
            UNUserNotificationCenter.current().delegate = self
        } else {
            // This handles the case where a delegate may have already been assigned before our SDK is loaded into memory.
            // This re-assignment triggers NotifiationCenter.delegate setter that we swizzled so our SDK can swizzle in its logic.
            UNUserNotificationCenter.current().delegate = UNUserNotificationCenter.current().delegate
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
}

// UNUserNotificationCenterDelegate functions
extension PushClickHandlerImpl {
    // Notification was interacted with.
    @objc public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        _ = MessagingPush.shared.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
    }
}

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

    // Swizzled method that gets called when a push notification gets clicked on
    @objc dynamic func cio_swizzle_didReceive(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        _ = MessagingPush.shared.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)

        // TODO: duplicate metrics could be reported because we might be swizzling multiple delegates and so this function gets called X number of times.
        // https://github.com/customerio/issues/issues/11150 should we do this?

        // continue swizzle
        cio_swizzle_didReceive(center, didReceive: response, withCompletionHandler: completionHandler)
    }
}
