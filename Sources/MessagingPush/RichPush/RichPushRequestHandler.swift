import CioInternalCommon
import Foundation

class RichPushRequestHandler {
    static let shared = RichPushRequestHandler()

    @Atomic private var requests: [String: RichPushRequest] = [:]

    private init() {}

    func startRequest(
        push: PushNotification
    ) async -> PushNotification? {
        let requestId = push.pushId

        let existingRequest = requests[requestId]
        if existingRequest != nil { return nil }

        let diGraph = DIGraphShared.shared
        let httpClient = diGraph.httpClient

        let newRequest = RichPushRequest(
            push: push,
            httpClient: httpClient
        )
        requests[requestId] = newRequest

        return await newRequest.start()
    }

    func stopAll() {
        requests.forEach {
            $0.value.finishImmediately()
        }

        requests = [:]
    }
}
