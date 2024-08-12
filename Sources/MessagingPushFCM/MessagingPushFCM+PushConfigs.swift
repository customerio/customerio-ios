import CioMessagingPush
import FirebaseCore
import FirebaseMessaging
import Foundation
#if canImport(UIKit)
import UIKit
#endif

extension MessagingPushFCM: AppDelegateSwizzlerDelegate {
    public func didReceiveAPNSToken(_ deviceToken: Data) {
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

    @available(iOSApplicationExtension, unavailable)
    func setupAutoFetchDeviceToken() {
        AppDelegateSwizzler.startSwizzling(self)
        UIApplication.shared.registerForRemoteNotifications()
    }
}
