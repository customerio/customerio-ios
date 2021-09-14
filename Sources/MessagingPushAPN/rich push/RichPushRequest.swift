import CioMessagingPush
import Foundation
#if canImport(UserNotifications)
import UserNotifications

@available(iOS 10.0, *)
internal class RichPushRequest {
    private let payload: RichPushPayload
    private let completionHandler: (UNNotificationContent) -> Void
    private let pushContent: PushContent

    init(
        payload: RichPushPayload,
        request: UNNotificationRequest,
        completionHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.payload = payload
        self.completionHandler = completionHandler
        self.pushContent = PushContent(notificationContent: request.content)

        start()
    }

    func start() {
        pushContent.deepLink = payload.deepLink
    }

    func finishImmediately() {
        completionHandler(pushContent.notificationContent)
    }
}
#endif
