import CioInternalCommon
import Foundation

class RichPushRequestHandler {
    nonisolated(unsafe) static let shared = RichPushRequestHandler()

    private var requests = EnhancedSynchronized<[String: RichPushRequest]>([:])

    private init() {}

    func startRequest(
        push: PushNotification
    ) async -> PushNotification? {
        let requestId = push.pushId

        // Atomic check-and-create operation with return value
        let newRequest: RichPushRequest? = requests.mutate { dict in
            // If already exists, return nil (no new request)
            if dict[requestId] != nil {
                return nil
            }

            // Create and store new request atomically
            let diGraph = DIGraphShared.shared
            let httpClient = diGraph.httpClient

            let request = RichPushRequest(
                push: push,
                httpClient: httpClient
            )

            dict[requestId] = request
            return request
        }

        // If no new request was created (already existed), return nil
        guard let request = newRequest else { return nil }

        return await request.start()
    }

    func stopAll() {
        requests.get().forEach {
            $0.value.finishImmediately()
        }

        requests.set([:])
    }
}
