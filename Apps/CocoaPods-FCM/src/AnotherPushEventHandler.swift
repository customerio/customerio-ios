import CioDataPipelines
import Foundation
import UIKit

class AnotherPushEventHandler: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        CustomerIO.shared.track(
            name: "push clicked",
            properties: [
                "push": response.notification.request.content.userInfo,
                "handler": "3rdPartyPushEventHandler"
            ]
        )

        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        CustomerIO.shared.track(
            name: "push should show app in foreground",
            properties: [
                "push": notification.request.content.userInfo,
                "handler": "3rdPartyPushEventHandler"
            ]
        )

        completionHandler([.banner, .badge, .sound])
    }
}
