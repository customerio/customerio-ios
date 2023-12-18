import Foundation
import UserNotifications

extension UNNotificationResponse {
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
}

extension UNNotification {
    var pushId: String {
        // Unique ID for each push notification.
        request.identifier
    }
}
