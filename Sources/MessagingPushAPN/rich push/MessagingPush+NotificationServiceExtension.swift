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
        // check if this request is one of Cio.
        // save content handler
        // save
    }

    func serviceExtensionTimeWillExpire() {
        // get all pending requests for extension and get it done! call completion handler.
        // so, i'll need a singleton handler for all didReceive requests because of this function.
    }
}
#endif
