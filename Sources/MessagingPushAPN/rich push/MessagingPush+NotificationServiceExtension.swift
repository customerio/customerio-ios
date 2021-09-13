import CioMessagingPush
import Foundation
import UserNotifications

@available(iOS 10.0, *)
public extension MessagingPush {
    func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        // save content handler
        // save
    }

    func serviceExtensionTimeWillExpire() {
        // get all pending requests for extension and get it done! call completion handler.
        // so, i'll need a singleton handler for all didReceive requests because of this function.
    }
}
