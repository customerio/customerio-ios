import CioMessagingPush
import CioTracking
import Foundation

public protocol MessagingPushFCMInstance: AutoMockable {
    // sourcery:Name=didReceiveRegistrationToken
    func messaging(
        _ messaging: Any,
        didReceiveRegistrationToken fcmToken: String?
    )

    // sourcery:Name=didFailToRegisterForRemoteNotifications
    func application(
        _ application: Any,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    )
}

/**
 MessagingPush extension to support FCM push notification messaging.
  */
extension MessagingPush: MessagingPushFCMInstance {
    public func messaging(
        _ messaging: Any,
        didReceiveRegistrationToken fcmToken: String?
    ) {
        guard let deviceToken = fcmToken else {
            return // ignore if token nil
        }
        registerDeviceToken(deviceToken)
    }

    public func application(
        _ application: Any,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        deleteDeviceToken()
    }
}

// sourcery: InjectRegister = "DiPlaceholder"
internal class DiPlaceholder {}
