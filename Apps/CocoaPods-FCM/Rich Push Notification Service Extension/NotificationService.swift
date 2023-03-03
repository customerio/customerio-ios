import CioMessagingPushFCM
import CioTracking
import UserNotifications

class NotificationService: UNNotificationServiceExtension {

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        CustomerIO.initialize(siteId: "", apiKey: "", region: .US) { config in
            config.logLevel = .debug
        }
        
        MessagingPush.shared.didReceive(request, withContentHandler: contentHandler)
    }

    override func serviceExtensionTimeWillExpire() {
        MessagingPush.shared.serviceExtensionTimeWillExpire()
    }
}
