import CioMessagingPushFCM
import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        // For simple apps that only use Customer.io for sending rich push messages,
        // This 1 line of code is all that you need!
        MessagingPush.shared.didReceive(request, withContentHandler: contentHandler)

        // If you use a service other than Customer.io to send rich push,
        // you can check if the SDK handled the rich push for you. If it did not, you
        // know that the push was *not* sent by Customer.io and you can try another way.
        let handled = MessagingPush.shared.didReceive(request, withContentHandler: contentHandler)
        if !handled {
            // Rich push was *not* sent by Customer.io. Handle the rich push in another way.
        }
        // If you need to add features, like showing action buttons in your push,
        // you can set your own completion handler.
        MessagingPush.shared.didReceive(request) { notificationContent in
            if let mutableContent = notificationContent.mutableCopy() as? UNMutableNotificationContent {
                // Modify the push notification like adding action buttons!
            }
            contentHandler(notificationContent)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        MessagingPush.shared.serviceExtensionTimeWillExpire()
    }
}
