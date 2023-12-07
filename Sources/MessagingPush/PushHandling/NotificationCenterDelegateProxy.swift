import Foundation
import UserNotifications

/*
 Because the CIO SDK forces itself to be the app's only push click handler, we want our SDK to still be compatible with other SDKs that also need to handle pushes being clicked.

 This class is a proxy that forwards requests to all other click handlers that have been registered with the app. Including 3rd party SDKs.
 */
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
