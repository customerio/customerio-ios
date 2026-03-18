import CioInternalCommon
import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

#if canImport(UserNotifications)

/// Abstraction for rich push in the NSE (`UNNotificationRequest` → content) so the coordinator can be tested with a mock.
protocol RichPushRequestHandling: AnyObject {
    func start(
        request: UNNotificationRequest,
        completion: @escaping (Result<UNNotificationContent, Error>) -> Void
    )

    func stopAll()
}

/// Rich push for one NSE coordinator: shares a dedicated `HttpClient` with delivery metrics and coordinator `cancel()`.
final class NSEPushRichPushRequestHandler: RichPushRequestHandling {
    private let httpClient: HttpClient
    private let requestHandler = RichPushRequestHandler()

    init(httpClient: HttpClient) {
        self.httpClient = httpClient
    }

    func start(
        request: UNNotificationRequest,
        completion: @escaping (Result<UNNotificationContent, Error>) -> Void
    ) {
        let push = UNNotificationWrapper(notificationRequest: request)
        requestHandler.startRequest(push: push, httpClient: httpClient) { composed in
            if let wrapper = composed as? UNNotificationWrapper {
                completion(.success(wrapper.notificationContent))
            } else {
                completion(.success(push.notificationContent))
            }
        }
    }

    func stopAll() {
        requestHandler.stopAll()
    }
}

#endif
