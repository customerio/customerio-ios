import Common
import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

// Exists to provide the ability to mock.
// Some functions in the Messaging Push module do not exist in here.
// The missing functions are ones that either:
// 1. Cannot be used in an App Extension so therefore, we cannot guarantee that the function
//    exists in the SDK code at compile time.
public protocol MessagingPushInstance {
    func registerDeviceToken(_ deviceToken: String)
    func deleteDeviceToken()
    func trackMetric(
        deliveryID: String,
        event: Metric,
        deviceToken: String
    )

    #if canImport(UserNotifications)
    // Used for rich push
    @discardableResult
    func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) -> Bool

    // Used for rich push
    func serviceExtensionTimeWillExpire()
    #endif
}
