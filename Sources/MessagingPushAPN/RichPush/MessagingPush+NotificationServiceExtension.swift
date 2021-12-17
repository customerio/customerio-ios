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

        let diGraph = DITracking.getInstance(siteId: siteId)
        let sdkConfig = diGraph.sdkConfigStore.config
        let jsonAdapter = diGraph.jsonAdapter

        if sdkConfig.autoTrackPushEvents {
            trackMetric(notificationContent: request.content, event: .delivered)
        }

        guard let pushContent = PushContent.parse(notificationContent: request.content,
                                                  jsonAdapter: jsonAdapter)
        else {
            // push does not contain a CIO rich payload, so end early
            return false
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
