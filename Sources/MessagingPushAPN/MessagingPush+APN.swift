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
 Convenient extensions so singleton instances of `MessagingPush` can access functions from `MessagingPushAPN`.
  */
extension MessagingPush: MessagingPushAPNInstance {
    public func registerDeviceToken(apnDeviceToken: Data) {
        MessagingPushAPN(customerIO: customerIO).registerDeviceToken(apnDeviceToken: apnDeviceToken)
    }

    public func application(
        _ application: Any,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        MessagingPushAPN(customerIO: customerIO)
            .application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    public func application(
        _ application: Any,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        MessagingPushAPN(customerIO: customerIO)
            .application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    }

    #if canImport(UserNotifications)
    @discardableResult
    public func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) -> Bool {
        MessagingPushAPN(customerIO: customerIO)
            .didReceive(request, withContentHandler: contentHandler)
    }

    public func serviceExtensionTimeWillExpire() {
        MessagingPushAPN(customerIO: customerIO).serviceExtensionTimeWillExpire()
    }
    #endif
}
