import CioMessagingPush
import Foundation
#if canImport(UserNotifications)
import UserNotifications

@available(iOS 10.0, *)
internal class RichPushRequest {
    private let completionHandler: (UNNotificationContent) -> Void
    private let pushContent: PushContent

    init(
        pushContent: PushContent,
        request: UNNotificationRequest,
        completionHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.completionHandler = completionHandler
        self.pushContent = pushContent
    }

    func start() {
        // no async operations or modifications to the notification to do. Therefore, let's just finish.

        finishImmediately()
    }

    func finishImmediately() {
        if let notificationContent = pushContent.mutableNotificationContent {
            completionHandler(notificationContent)
        }
    }
}
#endif
