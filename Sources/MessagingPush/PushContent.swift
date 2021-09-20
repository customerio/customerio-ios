import Foundation
#if canImport(UserNotifications)
import UserNotifications

/**
 The content of a push notification. Single source of truth for getting and setting properties of a push notification.

 Meant to be used by the SDK to set/get the push content but also designed for SDK user to further modify the push
 if they wish.
 */
@available(iOS 10.0, *)
public class PushContent {
    public var title: String {
        didSet {
            modifyNotificationContent()
        }
    }

    public var body: String {
        didSet {
            modifyNotificationContent()
        }
    }

    public var deepLink: URL? {
        didSet {
            modifyNotificationContent()
        }
    }

    public let mutableNotificationContent: UNMutableNotificationContent?

    public static func parse(notificationContent: UNNotificationContent) -> PushContent? {
        let raw = notificationContent.userInfo

        guard let cio = raw["CIO"] as? [AnyHashable: Any], let cioPush = cio["push"] as? [AnyHashable: Any] else {
            // Not a push sent by Customer.io
            return nil
        }

        return PushContent(notificationContent: notificationContent, cio: cio, cioPush: cioPush)
    }

    // Used when modifying push content before showing and for parsing after displaying.
    public init(notificationContent: UNNotificationContent, cio: [AnyHashable: Any], cioPush: [AnyHashable: Any]) {
        self.mutableNotificationContent = notificationContent.mutableCopy() as? UNMutableNotificationContent

        // For parsing after displaying, populate based off of content known now.
        self.title = notificationContent.title
        self.body = notificationContent.body
        self.deepLink = (cioPush["link"] as? String)?.url
    }

    private func modifyNotificationContent() {
        mutableNotificationContent?.title = title
        mutableNotificationContent?.body = body

        let cioMutableContent = mutableNotificationContent?.userInfo["CIO"] as? [AnyHashable: Any]
        var cioPushMutableContent = cioMutableContent?["push"] as? [AnyHashable: Any]

        cioPushMutableContent?["link"] = deepLink?.absoluteString
    }
}
#endif
