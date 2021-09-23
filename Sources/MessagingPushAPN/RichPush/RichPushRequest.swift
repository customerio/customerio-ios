import CioMessagingPush
import Foundation
#if canImport(UserNotifications)
import UserNotifications

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
        // XXX: stop async operations and finish the rich push request.

        completionHandler(pushContent.mutableNotificationContent)
    }
}
#endif
