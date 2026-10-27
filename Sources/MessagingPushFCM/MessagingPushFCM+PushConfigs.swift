import CioInternalCommon
@_spi(Internal) import CioMessagingPush
import Foundation
#if canImport(UIKit)
import UIKit
#endif

extension MessagingPushFCM {
    @available(iOSApplicationExtension, unavailable)
    func setupAutoFetchDeviceToken() {
        swizzleDidRegisterForRemoteNotifications(of: UIApplication.shared.delegate)
        UIApplication.shared.registerForRemoteNotifications()
    }

    @available(iOSApplicationExtension, unavailable)
    func swizzleDidRegisterForRemoteNotifications(of appDelegate: UIApplicationDelegate?) {
        AppDelegateSwizzler.swizzleDidRegisterForRemoteNotifications(of: appDelegate) { [weak self] application, deviceToken in
            self?.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
        }
    }

    // Runs after the app delegate's own `didRegisterForRemoteNotificationsWithDeviceToken`.
    // Fetch the FCM registration when the APN token is set.
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        fetchFirebaseRegistration(apnsToken: deviceToken) { [weak self] registration, tokenType in
            self?.registerFirebaseDeviceToken(registration, tokenType: tokenType)
        }
    }
}
