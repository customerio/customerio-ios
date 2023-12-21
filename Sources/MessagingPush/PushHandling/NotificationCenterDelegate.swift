import Foundation
import UserNotifications

protocol PushEventListener {
    var delegate: UNUserNotificationCenterDelegate { get }

    func onPushClicked(_ push: PushNotification, completionHandler: @escaping () -> Void)
    func shouldDisplayPushAppInForeground(_ push: PushNotification, completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)

    func newNotificationCenterDelegateSet(_ newDelegate: UNUserNotificationCenterDelegate?)
    func beginListening()
}

struct PushNotification {
    let pushId: String
    let deliveryDate: Date
    let title: String
    let message: String
    let data: [AnyHashable: Any]

    init(notification: UNNotification) {
        self.pushId = notification.request.identifier
        self.deliveryDate = notification.date
        self.title = notification.request.content.title
        self.message = notification.request.content.body
        self.data = notification.request.content.userInfo
    }
}

class BaseSdkPushEventListener: NSObject, UNUserNotificationCenterDelegate, PushEventListener {
    var delegate: UNUserNotificationCenterDelegate {
        self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        onPushClicked(PushNotification(notification: response.notification), completionHandler: completionHandler)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        shouldDisplayPushAppInForeground(PushNotification(notification: notification), completionHandler: completionHandler)
    }

    func onPushClicked(_ push: PushNotification, completionHandler: @escaping () -> Void) {
        fatalError("forgot to override in subclass")
    }

    func shouldDisplayPushAppInForeground(_ push: PushNotification, completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        fatalError("forgot to override in subclass")
    }
}
