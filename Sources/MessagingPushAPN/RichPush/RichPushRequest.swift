import CioMessagingPush
import CioTracking
import Foundation
#if canImport(UserNotifications)
import UserNotifications

internal class RichPushRequest {
    private let completionHandler: (UNNotificationContent) -> Void
    private let pushContent: PushContent
    private let httpClient: HttpClient

    init(
        pushContent: PushContent,
        request: UNNotificationRequest,
        httpClient: HttpClient,
        completionHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.completionHandler = completionHandler
        self.pushContent = pushContent
        self.httpClient = httpClient
    }

    func start() {
        guard let image = pushContent.image else {
            // no async operations or modifications to the notification to do. Therefore, let's just finish.
            return finishImmediately()
        }

        httpClient.downloadFile(url: image) { [weak self] localFilePath in
            guard let self = self else { return }

            if let localFilePath = localFilePath {
                self.pushContent.addImage(localFilePath: localFilePath)
            }

            self.finishImmediately()
        }
    }

    func finishImmediately() {
        httpClient.cancel(finishTasks: false)

        if let notificationContent = pushContent.mutableNotificationContent {
            completionHandler(notificationContent)
        }
    }
}
#endif
