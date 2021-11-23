import Foundation
import CioTracking
#if canImport(UserNotifications) && canImport(UIKit)
import UIKit
import UserNotifications

/**
 For rich push handling. Methods to call when a rich push UI is interacted with.
 */
public extension MessagingPush {
    /**
     A push notification was interacted with.

     - returns: If the SDK called the completion handler for you indicating if the SDK took care of the request or not.
     */
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) -> Bool {
        guard let siteId = customerIO.siteId else {
            completionHandler()
            return false
        }

        let diGraph = DI.getInstance(siteId: siteId)
        let sdkConfig = diGraph.sdkConfigStore.config
        let jsonAdapter = diGraph.jsonAdapter

        if sdkConfig.autoTrackPushEvents {
            var pushMetric = Metric.delivered

            if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                pushMetric = Metric.opened
            }

            trackMetric(notificationContent: response.notification.request.content, event: pushMetric) { _ in
                // XXX: pending background queue so that this can get retried instead of discarding the result
            }
        }

        // Time to handle rich push notifications.
        guard let pushContent = PushContent.parse(notificationContent: response.notification.request.content,
                                                  jsonAdapter: jsonAdapter)
        else {
            // push does not contain a CIO rich payload, so end early
            return false
        }

        switch response.actionIdentifier {
        case UNNotificationDismissActionIdentifier, UNNotificationDefaultActionIdentifier:
            cleanup(pushContent: pushContent)

        case UNNotificationDefaultActionIdentifier: // push notification was touched.
            if let deepLinkurl = pushContent.deepLink {
                UIApplication.shared.open(url: deepLinkurl)

                completionHandler()

                return true
            }
        default: break
        }

        return false
    }

    func trackMetric(
        notificationContent: UNNotificationContent,
        event: Metric,
        onComplete: @escaping (Result<Void, CustomerIOError>) -> Void
    ) {
        guard let deliveryID: String = notificationContent.userInfo["CIO-Delivery-ID"] as? String,
              let deviceToken: String = notificationContent.userInfo["CIO-Delivery-Token"] as? String
        else {
            return onComplete(Result.success(()))
        }

        trackMetric(deliveryID: deliveryID, event: event, deviceToken: deviceToken, onComplete: onComplete)
    }

    private func cleanup(pushContent: PushContent) {
        pushContent.cioAttachments.forEach { attachment in
            let localFilePath = attachment.url

            try? FileManager.default.removeItem(at: localFilePath)
        }
    }
}
#endif
