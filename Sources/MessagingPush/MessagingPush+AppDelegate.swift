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
        // A hack to get an instance of pushClickHandler without making it a property of the MessagingPushImplementation class. pushClickHandler is not available to app extensions but MessagingPushImplementation is.
        // We get around this by getting a instance in this function, only.
        if let pushClickHandler = sdkInitializedUtil.postInitializedData?.diGraph.pushClickHandler {
            return pushClickHandler.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
        }

        return false
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) -> CustomerIOParsedPushPayload? {
        // A hack to get an instance of pushClickHandler without making it a property of the MessagingPushImplementation class. pushClickHandler is not available to app extensions but MessagingPushImplementation is.
        // We get around this by getting a instance in this function, only.
        if let pushClickHandler = sdkInitializedUtil.postInitializedData?.diGraph.pushClickHandler {
            return pushClickHandler.userNotificationCenter(center, didReceive: response)
        }

        return nil
    }
}
#endif
