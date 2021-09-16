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

    public var notificationContent: UNMutableNotificationContent? {
        didSet {
            modifyNotificationContent()
        }
    }

    // Used when modifying push content before showing and for parsing after displaying.
    public init(notificationContent: UNNotificationContent) {
        self.notificationContent = notificationContent.mutableCopy() as? UNMutableNotificationContent

        // For parsing after displaying, populate based off of content known now.
        self.title = notificationContent.title
        self.body = notificationContent.body
        self.deepLink = (notificationContent.userInfo[UserInfoKey.deepLink.rawValue] as? String)?.url
    }

    private func modifyNotificationContent() {
        notificationContent?.title = title
        notificationContent?.body = body
        notificationContent?.userInfo[UserInfoKey.deepLink.rawValue] = deepLink
    }

    enum UserInfoKey: String {
        case deepLink
    }
}
#endif
