import CioMessagingPush
import CioTracking
import Foundation
#if canImport(UserNotifications)
import UserNotifications

/**
 Functions called in app's Notification Service target.
 */
public extension MessagingPush {
    /**
     - returns:
     Bool indicating if this push notification is one handled by Customer.io SDK or not.
     If function returns `false`, `contentHandler` will *not* be called by the SDK.
     */
    @discardableResult
    func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) -> Bool {
        
        guard let siteId = customerIO.siteId else {
            contentHandler(request.content)
            return false
        }

        let diGraph = DI.getInstance(siteId: siteId)
        var store  = diGraph.globalDataStore
        let sdkConfig = diGraph.sdkConfigStore.config
        let jsonAdapter = diGraph.jsonAdapter

        if sdkConfig.autoTrackPushEvents {
            trackMetric(notificationContent: request.content, event: .delivered) { _ in
                // XXX: pending background queue so that this can get retried instead of discarding the result
            }
        }

        guard let pushContent = PushContent.parse(notificationContent: request.content,
                                                  jsonAdapter: jsonAdapter)
        else {
            // push does not contain a CIO rich payload, so end early
            return false
        }

        // If cioHandleBadge exists and value is true
        if let cioHandleBadge = pushContent.cioHandleBadge, cioHandleBadge  {
            
            let badgeCount = store.badgeCount ?? 0
            // Update badge count in payload
            if let newRequest = request.content.mutableCopy() as? UNMutableNotificationContent {
                newRequest.badge = NSNumber(value: badgeCount + 1)
                store.badgeCount = badgeCount + 1
                contentHandler(newRequest)
            }
        }
        
        RichPushRequestHandler.shared.startRequest(request, content: pushContent, siteId: siteId,
                                                   completionHandler: contentHandler)

        return true
    }

    /**
     iOS OS telling the notification service to hurry up and stop modifying the push notifications.
     Stop all network requests and modifying and show the push for what it looks like now.
     */
    func serviceExtensionTimeWillExpire() {
        RichPushRequestHandler.shared.stopAll()
    }
}
#endif
