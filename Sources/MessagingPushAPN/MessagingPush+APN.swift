import CioMessagingPush
import Foundation

#if canImport(UserNotifications)
    import UserNotifications
#endif

/// Convenient extensions so singleton instances of `MessagingPush` can access functions from `MessagingPushAPN`.
extension MessagingPush: MessagingPushAPNInstance {
    public func registerDeviceToken(apnDeviceToken: Data) {
        MessagingPushAPN.shared.registerDeviceToken(apnDeviceToken: apnDeviceToken)
    }
}
