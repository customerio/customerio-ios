import Foundation

// A data type that represents a push notification.
// Note: This data class represents *all* push notifications, even those not sent by CIO.
public protocol PushNotification {
    var pushId: String { get }
    var deliveryDate: Date { get }
    var title: String { get }
    var message: String { get }
    var data: [AnyHashable: Any] { get }
}
