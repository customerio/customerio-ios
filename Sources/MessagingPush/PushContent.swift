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

    private let mutableContent: UNMutableNotificationContent?
    public private(set) var notificationContent: UNNotificationContent

    public init(notificationContent: UNNotificationContent) {
        self.mutableContent = notificationContent as? UNMutableNotificationContent
        self.notificationContent = notificationContent
        self.title = notificationContent.title
        self.body = notificationContent.body
        self.deepLink = (notificationContent.userInfo[UserInfoKey.deepLink.rawValue] as? String)?.url
    }

    private func modifyNotificationContent() {
        mutableContent?.title = title
        mutableContent?.body = body
        mutableContent?.userInfo[UserInfoKey.deepLink.rawValue] = deepLink
    }

    enum UserInfoKey: String {
        case deepLink
    }
}
#endif
