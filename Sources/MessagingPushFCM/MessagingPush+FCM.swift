import CioMessagingPush
import CioTracking
import Foundation

public protocol MessagingPushFCMInstance: AutoMockable {
    // sourcery:Name=didReceiveRegistrationToken
    func application(
        _ messaging: Any,
        didReceiveRegistrationToken fcmToken: String?,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    )

    // sourcery:Name=didFailToRegisterForRemoteNotifications
    func application(
        _ application: Any,
        didFailToRegisterForRemoteNotificationsWithError error: Error,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    )
}

/**
 MessagingPush extension to support FCM push notification messaging.
  */
public extension MessagingPush {
    func messaging(
        _ messaging: Any,
        didReceiveRegistrationToken fcmToken: String?,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        guard let deviceToken = fcmToken else {
            return onComplete(Result.success(()))
        }
        registerDeviceToken(deviceToken, onComplete: onComplete)
    }

    func application(
        _ application: Any,
        didFailToRegisterForRemoteNotificationsWithError error: Error,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        deleteDeviceToken(onComplete: onComplete)
    }
}
