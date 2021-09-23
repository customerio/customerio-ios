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
    func registerDeviceToken(apnDeviceToken: Data, onComplete: @escaping (Result<Void, CustomerIOError>) -> Void) {
        let deviceToken = String(apnDeviceToken: apnDeviceToken)
        return registerDeviceToken(deviceToken, onComplete: onComplete)
    }

    func application(
        _ application: Any,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        registerDeviceToken(apnDeviceToken: deviceToken, onComplete: onComplete)
    }

    func application(
        _ application: Any,
        didFailToRegisterForRemoteNotificationsWithError error: Error,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        deleteDeviceToken(onComplete: onComplete)
    }
}

// sourcery: InjectRegister = "DiPlaceholder"
internal class DiPlaceholder {}
