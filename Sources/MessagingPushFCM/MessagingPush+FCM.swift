import CioMessagingPush
import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/**
 Convenient extensions so singleton instances of `MessagingPush` can access functions from `MessagingPushFCM`.
 */
extension MessagingPush: MessagingPushFCMInstance {
    public func registerDeviceToken(fcmToken: String?) {
        MessagingPushFCM.shared.registerDeviceToken(fcmToken: fcmToken)
    }
}
