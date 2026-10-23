import CioInternalCommon
import Foundation
#if canImport(UIKit)
import UIKit
#endif

extension MessagingPushFCM {
    @available(iOSApplicationExtension, unavailable)
    func setupAutoFetchDeviceToken() {
        swizzleDidRegisterForRemoteNotifications()
        UIApplication.shared.registerForRemoteNotifications()
    }

    @available(iOSApplicationExtension, unavailable)
    private func swizzleDidRegisterForRemoteNotifications() {
        let appDelegate = UIApplication.shared.delegate
        let appDelegateClass: AnyClass? = object_getClass(appDelegate)
        let originalSelector = #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        let swizzledSelector = #selector(application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        swizzle(forOriginalClass: appDelegateClass, forSwizzledClass: MessagingPushFCM.self, original: originalSelector, new: swizzledSelector)
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
    // Fetch the FCM registration when the APN token is set.
    @objc
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Use Self.shared because after swizzling, `self` is the AppDelegate, not MessagingPushFCM
        Self.shared.fetchFirebaseRegistration(apnsToken: deviceToken) { registration, tokenType in
            Self.shared.registerFirebaseDeviceToken(registration, tokenType: tokenType)
        }
    }
}
