import CioMessagingPushFCM
import CioTracking
import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        MessagingPushFCM.initializeForExtension(
            withConfig: MessagingPushConfigBuilder(cdpApiKey: BuildEnvironment.CustomerIO.cdpApiKey)
                .build()
        )

        MessagingPush.shared.didReceive(request, withContentHandler: contentHandler)
    }

    override func serviceExtensionTimeWillExpire() {
        MessagingPush.shared.serviceExtensionTimeWillExpire()
    }
}
