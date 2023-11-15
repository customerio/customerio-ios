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
