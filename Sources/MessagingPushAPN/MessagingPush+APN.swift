import CioMessagingPush
import CioTracking
import Foundation

public protocol MessagingPushAPNInstance: AutoMockable {
    // sourcery:Name=registerAPNDeviceToken
    func registerDeviceToken(
        apnDeviceToken: Data,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    )

    // sourcery:Name=didRegisterForRemoteNotifications
    func application(
        _ application: Any,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data,
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
 MessagingPush extension to support APN push notification messaging.
  */
public extension MessagingPush {
    func registerDeviceToken(apnDeviceToken: Data) {
        let deviceToken = String(apnDeviceToken: apnDeviceToken)
        return registerDeviceToken(deviceToken)
    }

    func application(
        _ application: Any,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        registerDeviceToken(apnDeviceToken: deviceToken)
    }

    func application(
        _ application: Any,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        deleteDeviceToken()
    }
}

// sourcery: InjectRegister = "DiPlaceholder"
internal class DiPlaceholder {}
