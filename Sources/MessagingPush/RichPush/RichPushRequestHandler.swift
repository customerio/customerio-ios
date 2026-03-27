import CioInternalCommon
import Foundation

/// Handles rich-push image downloads for one logical scope (e.g. one NSE coordinator).
/// Use a dedicated instance per concurrent notification so `stopAll()` does not cancel other work.
class RichPushRequestHandler {
    @Atomic private var requests: [String: RichPushRequest] = [:]

    init() {}

    func startRequest(
        push: PushNotification,
        httpClient: HttpClient,
        completionHandler: @escaping (PushNotification) -> Void
    ) {
        guard let imageURLString = push.cioImage,
              !imageURLString.isEmpty,
              let imageURL = URL(string: imageURLString)
        else {
            completionHandler(push)
            return
        }

        let requestId = push.pushId

        if requests[requestId] != nil {
            // Same pushId already in flight; must complete so NSE coordinator continuations do not hang.
            completionHandler(push)
            return
        }

        let newRequest = RichPushRequest(
            push: push,
            imageURL: imageURL,
            httpClient: httpClient,
            completionHandler: completionHandler
        )
        requests[requestId] = newRequest

        newRequest.start()
    }

    func stopAll() {
        requests.forEach {
            $0.value.cancel()
        }

        requests = [:]
    }
}
