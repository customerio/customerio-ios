import CioMessagingPush
import CioTracking
import Foundation

public protocol MessagingPushAPNInstance: AutoMockable {
    // sourcery:Name=registerAPNDeviceToken
    func registerDeviceToken(apnDeviceToken: Data)

    // sourcery:Name=didRegisterForRemoteNotifications
    func application(
        _ application: Any,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    )

    // sourcery:Name=didFailToRegisterForRemoteNotifications
    func application(
        _ application: Any,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    )
}

/**
 MessagingPush extension to support APN push notification messaging.
  */
extension MessagingPush: MessagingPushAPNInstance {
    public func registerDeviceToken(apnDeviceToken: Data) {
        let deviceToken = String(apnDeviceToken: apnDeviceToken)
        return registerDeviceToken(deviceToken)
    }

    public func application(
        _ application: Any,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        registerDeviceToken(apnDeviceToken: deviceToken)
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
