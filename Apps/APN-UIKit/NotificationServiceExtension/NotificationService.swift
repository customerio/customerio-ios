import CioMessagingPushAPN
@preconcurrency import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @Sendable @escaping (UNNotificationContent) -> Void) {
        MessagingPushAPN.initializeForExtension(
            withConfig: MessagingPushConfigBuilder(cdpApiKey: BuildEnvironment.CustomerIO.cdpApiKey)
                .logLevel(.debug)
                .build()
        )

        Task { await MessagingPush.shared.didReceive(request, withContentHandler: contentHandler) }
    }

    override func serviceExtensionTimeWillExpire() {
        MessagingPush.shared.serviceExtensionTimeWillExpire()
    }
}
