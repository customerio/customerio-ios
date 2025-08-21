import CioInternalCommon
import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

// Exists to provide the ability to mock.
// Some functions in the Messaging Push module do not exist in here.
// The missing functions are ones that either:
// 1. Cannot be used in an App Extension so therefore, we cannot guarantee that the function
//    exists in the SDK code at compile time.
public protocol MessagingPushInstance: AutoMockable {
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
    // sourcery:Name=didReceiveNotificationRequest
    // sourcery:IfCanImport=UserNotifications
    func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) -> Bool

    // Used for rich push
    // sourcery:IfCanImport=UserNotifications
    func serviceExtensionTimeWillExpire()
    #endif

    // Note: userNotificationCenter methods removed from protocol due to
    // @available(iOSApplicationExtension, unavailable) compatibility issues.
    // These methods are implemented as extensions on concrete types where needed.
}
