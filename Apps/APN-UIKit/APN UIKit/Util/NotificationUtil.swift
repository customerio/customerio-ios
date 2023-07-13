import Foundation
import UIKit

protocol NotificationUtility {
    func showPromptForPushPermission(completionHandler: @escaping (Bool) -> Void)
    func getPushPermission(completionHandler: @escaping (UNAuthorizationStatus) -> Void)
}

// sourcery: InjectRegister = "NotificationUtil"
class NotificationUtil: NotificationUtility {
    func showPromptForPushPermission(completionHandler: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound], completionHandler: { status, _ in
            completionHandler(status)
        })
    }

    func getPushPermission(completionHandler: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { status in
            completionHandler(status.authorizationStatus)
        }
    }
}
