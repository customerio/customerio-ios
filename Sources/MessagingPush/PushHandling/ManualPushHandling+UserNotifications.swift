import CioInternalCommon
import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/**
 Functions that customers can call when they want to perform manual push click handling.

 Example: MessagingPush.shared.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
 */

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
        guard let _: CustomerIOParsedPushPayload = userNotificationCenter(center, didReceive: response) else {
            // push not sent from CIO. Exit early without calling completionHandler so that customer calls it instead.

            return false
        }

        completionHandler()

        return true
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) -> CustomerIOParsedPushPayload? {
        guard let parsedPush = CustomerIOParsedPushPayload.parse(response: response, jsonAdapter: jsonAdapter) else {
            // push not sent from CIO.

            return nil
        }

        if response.didClickOnPush {
            manualPushClickHandling(cioPush: parsedPush)
        }

        return parsedPush
    }

    // Function that contains the logic for when a customer is wanting to manual handle a push click event.
    // Function created for logic to be testable since automated test suite crashes when trying to access some UserNotification framework classes such as UNUserNotificationCenter.
    func manualPushClickHandling(cioPush: CustomerIOParsedPushPayload) {
        // A hack to get an instance of pushClickHandler without making it a property of the MessagingPushImplementation class. pushClickHandler is not available to app extensions but MessagingPushImplementation is.
        // We get around this by getting a instance in this function, only.
        if let pushClickHandler = sdkInitializedUtil.postInitializedData?.diGraph.pushClickHandler {
            pushClickHandler.pushClicked(cioPush)
        }
    }
}
#endif
