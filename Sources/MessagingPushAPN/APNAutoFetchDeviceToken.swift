import Foundation
import UIKit

// sourcery: AutoMockable
@available(iOSApplicationExtension, unavailable)
protocol APNAutoFetchDeviceToken {
    func setup()
}

@available(iOSApplicationExtension, unavailable)
class APNAutoFetchDeviceTokenImpl: APNAutoFetchDeviceToken {
    private static var didSwizzle: Bool = false
    private let messagingPushAPN: MessagingPushAPNInstance

    init(messagingPushAPN: MessagingPushAPNInstance) {
        self.messagingPushAPN = messagingPushAPN
    }

    func setup() {
        guard !Self.didSwizzle else {
            return
        }

        Self.didSwizzle = true

        swizzleDidRegisterForRemoteNotifications()
        swizzleDidFailToRegisterForRemoteNofifications()

        // Register for push notifications to invoke`didRegisterForRemoteNotificationsWithDeviceToken` method
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func swizzleDidRegisterForRemoteNotifications() {
        let appDelegate = UIApplication.shared.delegate
        let appDelegateClass: AnyClass? = object_getClass(appDelegate)

        let originalSelector = #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        let swizzledSelector = #selector(application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        swizzle(forOriginalClass: appDelegateClass, forSwizzledClass: MessagingPushAPN.self, original: originalSelector, new: swizzledSelector)
    }

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
        messagingPushAPN.registerDeviceToken(apnDeviceToken: deviceToken)
    }

    // Swizzled method for `didFailToRegisterForRemoteNotificationsWithError'
    @objc
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        messagingPushAPN.deleteDeviceToken()
    }
}
