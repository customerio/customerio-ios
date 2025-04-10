import CioMessagingPushAPN
import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        MessagingPushAPN.initializeForExtension(
            withConfig: MessagingPushConfigBuilder(cdpApiKey: BuildEnvironment.CustomerIO.cdpApiKey)
                .logLevel(.debug)
                .build()
        )

        if MessagingPush.shared.didReceive(request, withContentHandler: contentHandler) == false {
            contentHandler(request.content)
            return
        }
            
    }

    override func serviceExtensionTimeWillExpire() {
        MessagingPush.shared.serviceExtensionTimeWillExpire()
    }
}
