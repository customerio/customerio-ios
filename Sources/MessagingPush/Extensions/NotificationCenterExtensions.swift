import Foundation
import UserNotifications

/**
 Extensions for classes inside of the iOS UserNotifications framework.
 */

extension UNNotificationResponse { // class provided when a push is clicked or swiped away
    var didClickOnPush: Bool {
        actionIdentifier == UNNotificationDefaultActionIdentifier
    }

    var didSwipeAwayPush: Bool {
        actionIdentifier == UNNotificationDismissActionIdentifier
    }
}

extension UNNotificationResponse {
    var pushId: String {
        notification.pushId
    }

    var pushDeliveryDate: Date {
        notification.date
    }
}

extension UNNotification {
    var pushId: String {
        // Unique ID for each push notification.
        request.identifier
    }
}
