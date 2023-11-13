import CioInternalCommon
import FirebaseCore
import FirebaseMessaging
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
        guard let appDelegateClass = object_getClass(appDelegate) else {
            return
        }
        let originalSelector = #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        let swizzledSelector = #selector(application(_:didRegisterForRemoteNotificationsWithDeviceToken:))

        swizzle(targetClass: appDelegateClass, targetSelector: originalSelector, myClass: MessagingPushFCM.self, mySelector: swizzledSelector)
    }

    // Swizzled method for APN device token.
    // Fetch the FCM token using the Firebase delegate method when the APN token is set.
    @objc dynamic func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        // Registers listener with FCM SDK to always have the latest FCM token.
        // Used to automatically register it with the SDK.
        Messaging.messaging().token(completion: { token, _ in
            guard let token = token else {
                return
            }
            Self.shared.registerDeviceToken(fcmToken: token)
        })
    }
}
