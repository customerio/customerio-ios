import CioMessagingPushAPN
import UserNotifications
import CioTracking

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        
        CustomerIO.initialize(siteId: Env.customerIOSiteId , apiKey: Env.customerIOApiKey, region: Region.US) { config in
            config.autoTrackPushEvents = true
        }
        
        MessagingPush.shared.didReceive(request, withContentHandler: contentHandler)
    }
    
    override func serviceExtensionTimeWillExpire() {
        MessagingPush.shared.serviceExtensionTimeWillExpire()
    }

}
