import CioMessagingPushFCM
import CioTracking
import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        // we are only using this sample app for testing it can compile so providing a siteid and apikey is not useful at the moment.
        CustomerIO.initialize(siteId: "", apiKey: "", region: .US) { config in
            config.logLevel = .debug
        }

        MessagingPush.shared.didReceive(request, withContentHandler: contentHandler)
    }

    override func serviceExtensionTimeWillExpire() {
        MessagingPush.shared.serviceExtensionTimeWillExpire()
    }
}
