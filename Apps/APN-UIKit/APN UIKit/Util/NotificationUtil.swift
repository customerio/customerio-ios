import Foundation
import UIKit

protocol NotificationUtility {
    func showPromptForPushPermission()
}

// sourcery: InjectRegister = "NotificationUtil"
class NotificationUtil: NotificationUtility {
    func showPromptForPushPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound], completionHandler: { _, _ in })
    }
    
    func getPushPermission(completionHandler : @escaping(UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { status in
            completionHandler(status.authorizationStatus)
        }
    }
}
