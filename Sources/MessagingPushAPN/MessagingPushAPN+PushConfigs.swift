import CioInternalCommon
import Foundation
import UIKit

extension MessagingPushAPN {
    func setupAutoFetchDeviceToken() {
        // Swizzle method `didRegisterForRemoteNotificationsWithDeviceToken`
        swizzleDidRegisterForRemoteNotifications()
        // Register for push notifications to invoke`didRegisterForRemoteNotificationsWithDeviceToken` method
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func swizzleDidRegisterForRemoteNotifications() {
        let appDelegate = UIApplication.shared.delegate
        guard let appDelegateClass = object_getClass(appDelegate) else {
            return
        }

        // Swizzle `didRegisterForRemoteNotificationsWithDeviceToken`
        let originalSelector = #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        let swizzledSelector = #selector(application(_:didRegisterForRemoteNotificationsWithDeviceToken:))

        swizzle(targetClass: appDelegateClass, targetSelector: originalSelector, myClass: MessagingPushAPN.self, mySelector: swizzledSelector)

        // Swizzle `didFailToRegisterForRemoteNotificationsWithError`
        let originalSelectorForDidFail = #selector(UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:))
        let swizzledSelectorForDidFail = #selector(application(_:didFailToRegisterForRemoteNotificationsWithError:))

        swizzle(targetClass: appDelegateClass, targetSelector: originalSelectorForDidFail, myClass: MessagingPushAPN.self, mySelector: swizzledSelectorForDidFail)
    }

    // Swizzled method for APN device token.
    @objc dynamic func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Self.shared.registerDeviceToken(apnDeviceToken: deviceToken)

        self.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken) // continue swizzle
    }

    // Swizzled method for `didFailToRegisterForRemoteNotificationsWithError'
    @objc dynamic func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        messagingPush.deleteDeviceToken()

        self.application(application, didFailToRegisterForRemoteNotificationsWithError: error) // continue swizzle
    }
}
