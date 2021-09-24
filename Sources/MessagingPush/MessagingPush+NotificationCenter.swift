import Foundation
#if canImport(UserNotifications) && canImport(UIKit)
import CioTracking
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
        guard let pushContent = PushContent.parse(notificationContent: response.notification.request.content,
                                                  jsonAdapter: DITracking.shared.jsonAdapter)
        else {
            return false
        }

        switch response.actionIdentifier {
        case UNNotificationDismissActionIdentifier, UNNotificationDefaultActionIdentifier:
            cleanup(pushContent: pushContent)

        case UNNotificationDefaultActionIdentifier: // push notification was touched.
            if let deepLinkurl = pushContent.deepLink {
                UIApplication.shared.open(url: deepLinkurl)
                
                if customerIO.sdkConfig.autoTrackPushEvents {
                    trackMetric(notificationContent: response.notification.request.content, event: .opened, jsonAdapter: DITracking.shared.jsonAdapter)
                }
                
                completionHandler()

                return true
            }
        case UNNotificationDismissActionIdentifier:
            if customerIO.sdkConfig.autoTrackPushEvents {
                trackMetric(notificationContent: response.notification.request.content, event: .delivered, jsonAdapter: DITracking.shared.jsonAdapter)
            }
        default: break
        }

        return false
    }

    func trackMetric(notificationContent: UNNotificationContent, event: Metric, jsonAdapter: JsonAdapter){
        
        guard let deliveryID: String = notificationContent.userInfo["CIO-Delivery-ID"] as? String else {
            return
        }
        
        guard let deviceToken: String = notificationContent.userInfo["CIO-Delivery-Token"] as? String else {
            return
        }
        
        trackMetric(deliveryID: deliveryID, event: event, deviceToken: deviceToken) { result in
            // XXX: pending background queue so that this can get retried instead of discarding the result
        }
    }

    private func cleanup(pushContent: PushContent) {
        pushContent.cioAttachments.forEach { attachment in
            let localFilePath = attachment.url

            try? FileManager.default.removeItem(at: localFilePath)
        }
    }
}
#endif
