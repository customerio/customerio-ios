import Foundation
import UIKit

extension MessagingPushAPN {
    func setupAutoFetchDeviceToken() {
        let appDelegate = UIApplication.shared.delegate
        let appDelegateClass: AnyClass? = object_getClass(appDelegate)
        let originalSelector = #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        let swizzledSelector = #selector(application(_:didRegisterForRemoteNotificationsWithDeviceToken:))

        swizzle(forOriginalClass: appDelegateClass, forSwizzledClass: MessagingPushAPN.self, original: originalSelector, new: swizzledSelector)
    }

    private func swizzle(forOriginalClass: AnyClass?, forSwizzledClass: AnyClass?, original: Selector, new: Selector) {
        guard let originalMethod = class_getInstanceMethod(forOriginalClass, original) else { return }
        guard let swizzledMethod = class_getInstanceMethod(forSwizzledClass, new) else { return }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    // Swizzled method for APN device token.
    @objc
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = String(apnDeviceToken: deviceToken)
        print(token)
//        Self.shared.registerDeviceToken(token)
    }
}
