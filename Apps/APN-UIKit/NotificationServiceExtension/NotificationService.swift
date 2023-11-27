import CioMessagingPushAPN
import CioTracking
import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        CustomerIO.initialize(siteId: BuildEnvironment.CustomerIO.siteId, apiKey: BuildEnvironment.CustomerIO.apiKey, region: Region.US) { config in
            config.autoTrackPushEvents = true
        }

        MessagingPush.shared.didReceive(request, withContentHandler: contentHandler)
    }

    override func serviceExtensionTimeWillExpire() {
        MessagingPush.shared.serviceExtensionTimeWillExpire()
    }
}
