import Foundation
import UserNotifications

/**
 The SDK's code is abstracted away from the iOS `UserNotifications` framework.

 This file contains code that runs in production. Code that makes the `UserNotifications` data types
 conform to all of the SDK's abstracted data types.

 All of these wrappers should be small and simple. Their only job is to convert data types between SDK's abstracted data types and `UserNotifications` data types.
 */

class UNNotificationResponseWrapper: PushNotificationAction {
    public let response: UNNotificationResponse

    var push: PushNotification {
        UNNotificationWrapper(notification: response.notification)
    }

    var didClickOnPush: Bool {
        response.didClickOnPush
    }

    init(response: UNNotificationResponse) {
        self.response = response
    }
}

class UNNotificationWrapper: PushNotification {
    public let notification: UNNotification

    var pushId: String {
        notification.request.identifier
    }

    var deliveryDate: Date {
        notification.date
    }

    var title: String {
        notification.request.content.title
    }

    var message: String {
        notification.request.content.body
    }

    var data: [AnyHashable: Any] {
        notification.request.content.userInfo
    }

    init(notification: UNNotification) {
        self.notification = notification
    }
}

class UNUserNotificationCenterDelegateWrapper: PushEventHandler {
    private let delegate: UNUserNotificationCenterDelegate

    init(delegate: UNUserNotificationCenterDelegate) {
        self.delegate = delegate
    }

    func onPushAction(_ pushAction: PushNotificationAction, completionHandler: @escaping () -> Void) {
        guard let userNotificationsWrapperInstance = pushAction as? UNNotificationResponseWrapper else {
            return
        }

        delegate.userNotificationCenter?(UNUserNotificationCenter.current(), didReceive: userNotificationsWrapperInstance.response, withCompletionHandler: completionHandler)
    }

    func shouldDisplayPushAppInForeground(_ push: PushNotification, completionHandler: @escaping (Bool) -> Void) {
        guard let unnotification = push as? UNNotificationWrapper else {
            return
        }

        delegate.userNotificationCenter?(UNUserNotificationCenter.current(), willPresent: unnotification.notification) { displayPushInForegroundOptions in
            let shouldShowPush = !displayPushInForegroundOptions.isEmpty

            completionHandler(shouldShowPush)
        }
    }
}
