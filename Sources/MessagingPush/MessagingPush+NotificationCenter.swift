import Foundation
#if canImport(UserNotifications) && canImport(UIKit)
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
        guard let pushContent = PushContent.parse(notificationContent: response.notification.request.content) else {
            return false
        }

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier: // push notification was touched.
            if let deepLinkurl = pushContent.deepLink {
                UIApplication.shared.open(url: deepLinkurl)

                completionHandler()

                return true
            }
        default: break
        }

        return false
    }

    /**
     SwiftUI app's way to open deep links opening up an app.

     [Learn more](https://developer.apple.com/documentation/swiftui/view/onopenurl(perform:))
     */
    func onOpenURL(_ url: URL) {
        // XXX: A deep link pressed. See if it's one that a CIO notification pressed and track it.
    }

    /**
     UIKit's way to open deep links opening up an app.

     [Learn more](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1623112-application)
     */
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) {
        // XXX: A deep link pressed. See if it's one that a CIO notification pressed and track it.
    }
}
#endif
