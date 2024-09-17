import CioInternalCommon
import Foundation

// sourcery: InjectRegisterShared = "QueueManager"
// sourcery: InjectSingleton
class QueueManager {
    private var keyValueStore: SharedKeyValueStorage
    private let gistQueueNetwork: GistQueueNetwork
    private let inAppMessageManager: InAppMessageManager
    private let logger: Logger

    private var cachedFetchUserQueueResponse: Data? {
        get {
            keyValueStore.data(.inAppUserQueueFetchCachedResponse)
        }
        set {
            keyValueStore.setData(newValue, forKey: .inAppUserQueueFetchCachedResponse)
        }
    }

    init(keyValueStore: SharedKeyValueStorage, gistQueueNetwork: GistQueueNetwork, inAppMessageManager: InAppMessageManager, logger: Logger) {
        self.keyValueStore = keyValueStore
        self.gistQueueNetwork = gistQueueNetwork
        self.inAppMessageManager = inAppMessageManager
        self.logger = logger
    }

    func clearCachedUserQueue() {
        cachedFetchUserQueueResponse = nil
    }

    func fetchUserQueue(state: InAppMessageState, completionHandler: @escaping (Result<[UserQueueResponse]?, Error>) -> Void) {
        do {
            try gistQueueNetwork.request(state: state, request: QueueEndpoint.getUserQueue, completionHandler: { response in
                switch response {
                case .success(let (data, response)):
                    self.updatePollingInterval(headers: response.allHeaderFields)
                    self.logger.logWithModuleTag("Gist queue fetch response: \(response.statusCode)", level: .debug)
                    switch response.statusCode {
                    case 304:
                        guard let lastCachedResponse = self.cachedFetchUserQueueResponse else {
                            return completionHandler(.success(nil))
                        }

                        do {
                            let userQueue = try self.parseResponseBody(lastCachedResponse)

                            completionHandler(.success(userQueue))
                        } catch {
                            completionHandler(.failure(error))
                        }
                    default:
                        do {
                            let userQueue = try self.parseResponseBody(data)

                            self.cachedFetchUserQueueResponse = data

                            completionHandler(.success(userQueue))
                        } catch {
                            completionHandler(.failure(error))
                        }
                    }
                case .failure(let error):
                    self.logger.logWithModuleTag("Gist queue fetch response failure: \(error)", level: .debug)
                    completionHandler(.failure(error))
                }
            })
        } catch {
            logger.logWithModuleTag("Gist queue fetch response error: \(error)", level: .debug)
            completionHandler(.failure(error))
        }
    }

    private func parseResponseBody(_ responseBody: Data) throws -> [UserQueueResponse] {
        if let userQueueResponse =
            try JSONSerialization.jsonObject(
                with: responseBody,
                options: .allowFragments
            ) as? [[String: Any?]] {
            return userQueueResponse.map { UserQueueResponse(dictionary: $0) }.mapNonNil()
        }

        return []
    }

    private func updatePollingInterval(headers: [AnyHashable: Any]) {
        guard let newPollingIntervalString = headers["x-gist-queue-polling-interval"] as? String,
              let newPollingInterval = Double(newPollingIntervalString) else { return }

        inAppMessageManager.fetchState { [weak self] state in
            guard let self = self, newPollingInterval != state.pollInterval else { return }

            logger.logWithModuleTag("Updating polling interval to: \(newPollingInterval) seconds", level: .debug)
            inAppMessageManager.dispatch(action: .setPollingInterval(interval: newPollingInterval))
        }
    }
}
