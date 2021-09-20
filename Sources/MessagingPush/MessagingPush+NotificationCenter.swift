import Foundation
#if canImport(UserNotifications) && canImport(UIKit)
import UIKit
import UserNotifications

public extension MessagingPush {
    /**
     A push notification was interacted with.

     - returns: If the SDK called the completion handler for you indicating if the SDK took care of the request or not.
     */
    @available(iOS 10.0, *)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) -> Bool {
        let pushContent = PushContent(notificationContent: response.notification.request.content)

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
        // A deep link pressed. See if it's one that a CIO notification pressed and track it.
    }

    /**
     UIKit's way to open deep links opening up an app.

     [Learn more](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1623112-application)
     */
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) {
        // A deep link pressed. See if it's one that a CIO notification pressed and track it.
    }
}
#endif
