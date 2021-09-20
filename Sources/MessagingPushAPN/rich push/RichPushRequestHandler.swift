import CioMessagingPush
import CioTracking
import Foundation
#if canImport(UserNotifications)
import UserNotifications

@available(iOS 10.0, *)
internal class RichPushRequestHandler {
    static let shared = RichPushRequestHandler()

    @Atomic private var requests: [String: RichPushRequest] = [:]

    private init() {}

    func startRequest(
        _ request: UNNotificationRequest,
        content: PushContent,
        completionHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let requestId = request.identifier

        let existingRequest = requests[requestId]
        if existingRequest != nil { return }

        let newRequest = RichPushRequest(pushContent: content, request: request, completionHandler: completionHandler)
        requests[requestId] = newRequest

        newRequest.start()
    }

    func stopAll() {
        requests.forEach { item in
            let request = item.value

            request.finishImmediately()
        }

        requests = [:]
    }
}
#endif
