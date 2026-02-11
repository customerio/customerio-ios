import Foundation
import UIKit

protocol NotificationUtility {
    func showPromptForPushPermission(completionHandler: @Sendable @escaping (Bool) -> Void)
    func getPushPermission(completionHandler: @Sendable @escaping (UNAuthorizationStatus) -> Void)
}

// sourcery: InjectRegisterShared = "NotificationUtil"
class NotificationUtil: NotificationUtility {
    func showPromptForPushPermission(completionHandler: @Sendable @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound], completionHandler: { status, _ in
            completionHandler(status)
        })
    }

    func getPushPermission(completionHandler: @Sendable @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { status in
            completionHandler(status.authorizationStatus)
        }
    }
}
