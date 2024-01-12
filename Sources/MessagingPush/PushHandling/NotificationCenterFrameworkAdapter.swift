import Foundation
import UserNotifications

/**
 The push features in the SDK interact with the iOS framework, `UserNotifications`.
 In order for us to write automated tests around our code that interacts with this framework, we treat `UserNotifications` as a dependency and mock it.

 This file is part of that by being the adapter between our SDK and the iOS framework.
 */

@available(iOSApplicationExtension, unavailable)
protocol NotificationCenterFrameworkAdapter {
    // A strongly typed reference to an instance of UNUserNotificationCenterDelegate that we can provide to iOS in producdtion.
    var delegate: UNUserNotificationCenterDelegate { get }
}

/**
 This class is an adapter that makes our SDK communicate with the iOS framework, `UserNotifications` in production.

 This allows our SDK to not have knowledge of the `UserNotifications` framework, which makes it easier to write automated tests around our SDK.

 Keep this class simple because it is only able to be tested in QA testing. It's meant to be an adapter, not contain logic.
 */
// sourcery: InjectRegister = "NotificationCenterFrameworkAdapter"
@available(iOSApplicationExtension, unavailable)
class NotificationCenterFrameworkAdapterImpl: NSObject, UNUserNotificationCenterDelegate, NotificationCenterFrameworkAdapter {
    private let pushEventListener: PushEventListener

    init(pushEventListener: PushEventListener) {
        self.pushEventListener = pushEventListener
    }

    var delegate: UNUserNotificationCenterDelegate {
        self
    }

    // Functions called by iOS framework, `UserNotifications`. This adapter class simply passes these requests to other code in our SDK where the logic exists.

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let wasClickEventHandled = pushEventListener.onPushAction(PushNotification(notification: response.notification), didClickOnPush: response.didClickOnPush)

        if wasClickEventHandled {
            // call the completion handler so the customer does not need to.
            completionHandler()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let response = pushEventListener.shouldDisplayPushAppInForeground(PushNotification(notification: notification))
        guard let shouldShowPush = response else {
            // push not handled by CIO SDK. Exit early. Another click handler will call the completion handler.

            return
        }

        if shouldShowPush {
            if #available(iOS 14.0, *) {
                completionHandler([.list, .banner, .badge, .sound])
            } else {
                completionHandler([.badge, .sound])
            }
        } else {
            completionHandler([])
        }
    }
}

// A class that represents a push notification received by the iOS framework, `UserNotifications`.
// When our SDK receives a push notification from the `UserNotification` framework, the push is converted into
// an instance of this class, first.
//
// This allows us to write automated tests around our SDK's push handling logic because classes inside of `UserUnotifications` internal and not mockable.
public struct PushNotification {
    let pushId: String
    let deliveryDate: Date
    let title: String
    let message: String
    let data: [AnyHashable: Any]
    let rawNotification: UNNotification

    init(notification: UNNotification) { // Parses a `UserNotification` framework class
        self.pushId = notification.request.identifier
        self.deliveryDate = notification.date
        self.title = notification.request.content.title
        self.message = notification.request.content.body
        self.data = notification.request.content.userInfo
        self.rawNotification = notification
    }
}
