import CioMessagingPush
import Foundation
#if canImport(UserNotifications)
import UserNotifications

@available(iOS 10.0, *)
public extension MessagingPush {
    /**
     - returns:
     Bool indicating if this push notification is one handled by Customer.io SDK or not.
     If function returns `false`, `contentHandler` will *not* be called by the SDK.
     */
    @discardableResult
    func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) -> Bool {
        guard let parsedRequest = RichPushProcessor.process(request) else {
            // push is not sent by CIO. Therefore, end early.
            print("push not sent by CIO. End early")
            return false
        }

        print("Push sent by CIO. starting request now")
        RichPushRequestHandler.shared.startRequest(request, payload: parsedRequest, completionHandler: contentHandler)

        return true
    }

    func serviceExtensionTimeWillExpire() {
        RichPushRequestHandler.shared.stopAll()
    }
}
#endif
