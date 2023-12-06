import Foundation
import UserNotifications

// TODO: add comment expkaining tjhs
public class NotificationCenterDelegateProxy: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationCenterDelegateProxy()

    // Use a map so that we only save 1 instance of a given Delegate.
    private var nestedDelegates: [String: UNUserNotificationCenterDelegate] = [:]

    func newNotificationCenterDelegateSet(_ newDelegate: UNUserNotificationCenterDelegate?) {
        guard let delegate = newDelegate else {
            return
        }

        let doesDelegateBelongToCio = delegate is NotificationCenterDelegateProxy

        guard !doesDelegateBelongToCio else {
            return
        }

        let nestedDelegateKey = String(describing: delegate)
        nestedDelegates[nestedDelegateKey] = delegate
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        nestedDelegates.forEach { _, delegate in
            delegate.userNotificationCenter?(center, didReceive: response, withCompletionHandler: completionHandler)
        }
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        nestedDelegates.forEach { _, delegate in
            delegate.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: completionHandler)
        }
    }
}
