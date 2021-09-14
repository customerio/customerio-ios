import CioTracking
import Foundation
#if canImport(UserNotifications)
import UserNotifications

@available(iOS 10.0, *)
internal enum RichPushProcessor {
    static func process(_ request: UNNotificationRequest) -> RichPushPayload? {
        let raw = request.content.userInfo

        let cio = raw["CIO"] as? [AnyHashable: Any]
        guard let cioPush = cio?["push"] as? [AnyHashable: Any] else {
            return nil // if there is no push payload, it's not a request from Customer.io
        }

        let link = cioPush["link"] as? String

        return RichPushPayload(deepLink: link?.url, title: nil, body: nil)
    }

    static func isValidCioRequest(_ request: UNNotificationRequest) -> Bool {
        process(request) != nil
    }
}
#endif
