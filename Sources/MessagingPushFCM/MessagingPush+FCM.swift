import CioMessagingPush
import CioTracking
import Firebase
import Foundation

/**
 MessagingPush extension to support APN push notification messaging.
  */
public extension MessagingPush {
    func messaging(
        _ messaging: Messaging,
        didReceiveRegistrationToken fcmToken: String?,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        guard let deviceToken = fcmToken else {
            return onComplete(Result.success(()))
        }

        let dataDict: [String: String] = ["token": fcmToken ?? ""]
        NotificationCenter.default.post(name: Notification.Name("FCMToken"),
                                        object: nil,
                                        userInfo: dataDict)
        registerDeviceToken(deviceToken.data, onComplete: onComplete)
    }

    func application(
        _ application: Any,
        didFailToRegisterForRemoteNotificationsWithError error: Error,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        deleteDeviceToken(onComplete: onComplete)
    }

    // If swizzling is disabled then this function should be called so that the APNs token can be paired to
    // the FCM registration token.
    func application(
        _ application: Any,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        registerDeviceToken(deviceToken, onComplete: onComplete)
        Messaging.messaging().apnsToken = deviceToken
    }
}
