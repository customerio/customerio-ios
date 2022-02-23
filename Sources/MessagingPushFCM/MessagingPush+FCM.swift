import CioMessagingPush
import CioTracking
import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

// Expose `MessagingPush` in module so customers do not need to `import CioMessaginPush`
// Only 1 import: `CioMessaginPushAPN`.
public typealias MessagingPush = CioMessagingPush.MessagingPush

/**
 Convenient extensions so singleton instances of `MessagingPush` can access functions from `MessagingPushFCM`.
 */
extension MessagingPush: MessagingPushFCMInstance {
    public func registerDeviceToken(fcmToken: String?) {
        MessagingPushFCM(customerIO: customerIO).registerDeviceToken(fcmToken: fcmToken)
    }

    public func messaging(
        _ messaging: Any,
        didReceiveRegistrationToken fcmToken: String?
    ) {
        MessagingPushFCM(customerIO: customerIO)
            .messaging(messaging, didReceiveRegistrationToken: fcmToken)
    }

    public func application(
        _ application: Any,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        MessagingPushFCM(customerIO: customerIO)
            .application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    }

    #if canImport(UserNotifications)
    @discardableResult
    public func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) -> Bool {
        MessagingPushFCM(customerIO: customerIO)
            .didReceive(request, withContentHandler: contentHandler)
    }

    public func serviceExtensionTimeWillExpire() {
        MessagingPushFCM(customerIO: customerIO).serviceExtensionTimeWillExpire()
    }
    #endif
}
