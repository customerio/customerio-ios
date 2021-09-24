import CioMessagingPush
import CioTracking
import Foundation
#if canImport(UserNotifications)
import UserNotifications

internal class RichPushRequestHandler {
    static let shared = RichPushRequestHandler()

    @Atomic private var requests: [String: RichPushRequest] = [:]

    private init() {}

    func startRequest(
        _ request: UNNotificationRequest,
        content: PushContent,
        customerIO: CustomerIO,
        completionHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let requestId = request.identifier

        let existingRequest = requests[requestId]
        if existingRequest != nil { return }

        // XXX: After we are able to inject HttpClient using DI graph, this is no longer needed.
        guard let credentials = customerIO.credentials else {
            return
        }
        let httpClient = CIOHttpClient(credentials: credentials, config: customerIO.sdkConfig)

        let newRequest = RichPushRequest(pushContent: content, request: request, httpClient: httpClient,
                                         completionHandler: completionHandler)
        requests[requestId] = newRequest

        newRequest.start()
    }

    func stopAll() {
        requests.forEach {
            $0.value.finishImmediately()
        }

        requests = [:]
    }
}
#endif
