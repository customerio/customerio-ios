import FirebaseCore
import FirebaseMessaging
import Foundation
#if canImport(UIKit)
import UIKit
#endif

extension MessagingPushFCM {
    @available(iOSApplicationExtension, unavailable)
    func setupAutoFetchDeviceToken() {
        // Set delegate
        //        Messaging.messaging().delegate = Self

        // Swizzle method `didRegisterForRemoteNotificationsWithDeviceToken`
        //        swizzleDidRegisterForRemoteNotifications()
        // Trying to fetch token again using firebase's methods
        swizzleDidRegisterForRemoteNotifications()
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
    @objc
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        Messaging.messaging().token(completion: { token, _ in
            guard let token = token else {
                print("SOME ERROR")
                return
            }
            // register token
        })
        // Self.shared.registerDeviceToken(apnDeviceToken: deviceToken)
    }
}

/*
     @available(iOSApplicationExtension, unavailable)
     private func swizzleDidRegisterForRemoteNotifications() {
         let appDelegate = MessagingDelegate.self
         let appDelegateClass: AnyClass? = object_getClass(appDelegate)
         let originalSelector = #selector(MessagingDelegate.messaging(_:didReceiveRegistrationToken:))
         let swizzledSelector = #selector(MessagingPushFCM.messaging(_:didReceiveRegistrationToken:))
         swizzle(forOriginalClass: appDelegateClass, forSwizzledClass: MessagingPushFCM.self, original: originalSelector, new: swizzledSelector)
     }

     private func swizzle(forOriginalClass: AnyClass?, forSwizzledClass: AnyClass?, original: Selector, new: Selector) {
         guard let swizzledMethod = class_getInstanceMethod(forSwizzledClass, new) else { return }
         guard let originalMethod = class_getInstanceMethod(forOriginalClass, original) else {
             // Add method if it doesn't exist
             class_addMethod(forOriginalClass, original, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))
             return
         }
         method_exchangeImplementations(originalMethod, swizzledMethod)
     }

     // Swizzled method for FCM device token.
     @objc
     func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
         print(fcmToken)
 //        Self.shared.registerDeviceToken(apnDeviceToken: deviceToken)
     }
 }

 //
 // extension MessagingPushFCM: MessagingDelegate {
 //    // FCM SDK calls this function when a FCM device token is available.
 //    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
 //        // Pass the FCM token to the Customer.io SDK:
 //        MessagingPush.shared.registerDeviceToken(fcmToken: fcmToken)
 //    }
 // }
 */
