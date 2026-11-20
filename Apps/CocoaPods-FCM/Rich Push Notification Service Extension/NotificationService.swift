import CioMessagingPushFCM
import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        MessagingPushFCM.initializeForExtension(
            withConfig: MessagingPushConfigBuilder(cdpApiKey: BuildEnvironment.CustomerIO.cdpApiKey)
                .logLevel(.debug)
                .build()
        )

        // Returns false for a push Customer.io didn't send (for example from another push provider) and never
        // calls the handler for it, so deliver that push unchanged.
        if !MessagingPush.shared.didReceive(request, withContentHandler: contentHandler) {
            contentHandler(request.content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        MessagingPush.shared.serviceExtensionTimeWillExpire()
    }
}
