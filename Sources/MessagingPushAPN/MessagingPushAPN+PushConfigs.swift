import Foundation
import UIKit

// sourcery: AutoMockable
protocol APNAutoFetchDeviceToken {
    func setup()
}

class APNAutoFetchDeviceTokenImpl: APNAutoFetchDeviceToken {
    private let messagingPushAPN: MessagingPushAPNInstance

    init(messagingPushAPN: MessagingPushAPNInstance) {
        self.messagingPushAPN = messagingPushAPN
    }

    @available(iOSApplicationExtension, unavailable)
    func setup() {
        swizzleDidRegisterForRemoteNotifications()
        swizzleDidFailToRegisterForRemoteNofifications()

        // Register for push notifications to invoke`didRegisterForRemoteNotificationsWithDeviceToken` method
        UIApplication.shared.registerForRemoteNotifications()
    }

    @available(iOSApplicationExtension, unavailable)
    private func swizzleDidRegisterForRemoteNotifications() {
        let appDelegate = UIApplication.shared.delegate
        let appDelegateClass: AnyClass? = object_getClass(appDelegate)

        let originalSelector = #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        let swizzledSelector = #selector(application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        swizzle(forOriginalClass: appDelegateClass, forSwizzledClass: MessagingPushAPN.self, original: originalSelector, new: swizzledSelector)
    }

    @available(iOSApplicationExtension, unavailable)
    private func swizzleDidFailToRegisterForRemoteNofifications() {
        let appDelegate = UIApplication.shared.delegate
        let appDelegateClass: AnyClass? = object_getClass(appDelegate)
        let originalSelectorForDidFail = #selector(UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:))
        let swizzledSelectorForDidFail = #selector(application(_:didFailToRegisterForRemoteNotificationsWithError:))
        swizzle(forOriginalClass: appDelegateClass, forSwizzledClass: MessagingPushAPN.self, original: originalSelectorForDidFail, new: swizzledSelectorForDidFail)
    }

    private func swizzle(forOriginalClass: AnyClass?, forSwizzledClass: AnyClass?, original: Selector, new: Selector) {
        guard let swizzledMethod = class_getInstanceMethod(forSwizzledClass, new) else { return }
        guard let originalMethod = class_getInstanceMethod(forOriginalClass, original) else {
            // Add method if it doesn't exist
            class_addMethod(forOriginalClass, new, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))
            return
        }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    // Swizzled method for APN device token.
    @objc
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
//        Self.shared.registerDeviceToken(apnDeviceToken: deviceToken)
        messagingPushAPN.registerDeviceToken(apnDeviceToken: deviceToken)
    }

    // Swizzled method for `didFailToRegisterForRemoteNotificationsWithError'
    @objc
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
//        MessagingPushAPN.shared.deleteDeviceToken()
        messagingPushAPN.deleteDeviceToken()
    }
}
