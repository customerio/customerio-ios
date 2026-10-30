@_spi(Internal) import CioMessagingPush
import Foundation
import UIKit

extension MessagingPushAPN {
    @available(iOSApplicationExtension, unavailable)
    func setupAutoFetchDeviceToken() {
        // Swizzle method `didRegisterForRemoteNotificationsWithDeviceToken`
        swizzleDidRegisterForRemoteNotifications(of: UIApplication.shared.delegate)
        // Register for push notifications to invoke`didRegisterForRemoteNotificationsWithDeviceToken` method
        UIApplication.shared.registerForRemoteNotifications()
    }

    @available(iOSApplicationExtension, unavailable)
    func swizzleDidRegisterForRemoteNotifications(of appDelegate: UIApplicationDelegate?) {
        // Swizzle `didRegisterForRemoteNotificationsWithDeviceToken`
        AppDelegateSwizzler.swizzleDidRegisterForRemoteNotifications(of: appDelegate) { [weak self] application, deviceToken in
            self?.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
        }

        // Swizzle `didFailToRegisterForRemoteNotificationsWithError`
        AppDelegateSwizzler.swizzleDidFailToRegisterForRemoteNotifications(of: appDelegate) { [weak self] application, error in
            self?.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
        }
    }

    // Runs after the app delegate's own `didRegisterForRemoteNotificationsWithDeviceToken`.
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Self.shared.registerDeviceToken(apnDeviceToken: deviceToken)
    }

    // Runs after the app delegate's own `didFailToRegisterForRemoteNotificationsWithError`.
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        MessagingPush.shared.didFailToRegisterForRemoteNotifications(error: error)
    }
}
