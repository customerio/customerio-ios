import Common
import Foundation
#if canImport(UserNotifications) && canImport(UIKit)
import UIKit
import UserNotifications
#endif

#if canImport(UserNotifications) && canImport(UIKit)
@available(iOSApplicationExtension, unavailable)
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
        guard let implementation = implementation else {
            completionHandler()
            return false
        }

        return implementation.userNotificationCenter(
            center,
            didReceive: response,
            withCompletionHandler: completionHandler
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) -> CustomerIOParsedPushPayload? {
        guard let implementation = implementation else {
            return nil
        }

        return implementation.userNotificationCenter(center, didReceive: response)
    }
}

@available(iOSApplicationExtension, unavailable)
extension MessagingPushImplementation {
    /**
     A push notification was interacted with.

     - returns: If the SDK called the completion handler for you indicating if the SDK took care of the request or not.
     */
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) -> Bool {
        guard let pushContent = userNotificationCenter(center, didReceive: response) else {
            // push did not come from CIO
            // Do not call completionHandler() because push did not come from CIO. Another service might have sent it so
            // allow another SDK
            // to call the completionHandler()
            return false
        }

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier: // push notification was touched.
            if let deepLinkurl = pushContent.deepLink {
                // First, try to open the link inside of the host app. This is to keep compatability with Universal Links.
                // Learn more of edge case: https://github.com/customerio/customerio-ios/issues/262
                // Fallback to opening the URL system-wide if fail to open link in host app.
                // Customers with Universal Links in their app will need to add this function to their `AppDelegate` which will get called with deep link:
                // func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool

                // fallback to open link in device browser
                let performDeepLinkFallback: () -> Void = {
                    self.logger.debug("Host app didn't handle link. Opening the link through a system call.")
                    UIApplication.shared.open(url: deepLinkurl)
                }

                logger.debug("Found a deep link inside of a push notification. \(deepLinkurl)")

                if deepLinkUtil.isLinkValidNSUserActivityLink(deepLinkurl) {
                    logger.debug("Attempting to open deep link in host app.")

                    let openLinkInHostAppActivity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
                    openLinkInHostAppActivity.webpageURL = deepLinkurl

                    let didHostAppHandleLink = UIApplication.shared.delegate?.application?(UIApplication.shared, continue: openLinkInHostAppActivity, restorationHandler: { _ in }) ?? false

                    if !didHostAppHandleLink {
                        performDeepLinkFallback()
                    }
                } else {
                    performDeepLinkFallback()
                }
            }
        default: break
        }

        // Push came from CIO and the SDK handled it. Therefore, call the completionHandler for the customer and return
        // true telling them that the SDK handled the push for them.
        completionHandler()
        return true
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) -> CustomerIOParsedPushPayload? {
        if sdkConfig.autoTrackPushEvents {
            var pushMetric = Metric.delivered

            if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                pushMetric = Metric.opened
            }

            trackMetric(notificationContent: response.notification.request.content, event: pushMetric)
        }

        // Time to handle rich push notifications.
        guard let pushContent = CustomerIOParsedPushPayload
            .parse(
                notificationContent: response.notification.request.content,
                jsonAdapter: jsonAdapter
            )
        else {
            // push does not contain a CIO rich payload, so end early
            return nil
        }

        cleanupAfterPushInteractedWith(pushContent: pushContent)

        return pushContent
    }
}
#endif
