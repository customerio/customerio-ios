import CioInternalCommon
import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

#if canImport(UserNotifications)
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
        // Time to handle rich push notifications.
        guard let pushContent = pushClickHandler.pushClicked(response: response) else {
            // push did not come from CIO
            // Do not call completionHandler() because push did not come from CIO. Another service might have sent it so
            // allow another SDK
            // to call the completionHandler()
            return false
        }

        completionHandler()
        return true
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) -> CustomerIOParsedPushPayload? {
        pushClickHandler.pushClicked(response: response)
    }
}
#endif
