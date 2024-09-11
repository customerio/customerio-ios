import CioInternalCommon
import Foundation

class QueueManager {
    let siteId: String
    let dataCenter: String
    var keyValueStore: SharedKeyValueStorage = DIGraphShared.shared.sharedKeyValueStorage
    let gistQueueNetwork: GistQueueNetwork = DIGraphShared.shared.gistQueueNetwork
    let threadUtil: ThreadUtil = DIGraphShared.shared.threadUtil

    private var cachedFetchUserQueueResponse: Data? {
        get {
            keyValueStore.data(.inAppUserQueueFetchCachedResponse)
        }
        set {
            keyValueStore.setData(newValue, forKey: .inAppUserQueueFetchCachedResponse)
        }
    }

    init(siteId: String, dataCenter: String) {
        self.siteId = siteId
        self.dataCenter = dataCenter
    }

    func clearCachedUserQueue() {
        cachedFetchUserQueueResponse = nil
    }

    func fetchUserQueue(userToken: String, completionHandler: @escaping (Result<[UserQueueResponse]?, Error>) -> Void) {
        do {
            try gistQueueNetwork.request(siteId: siteId, dataCenter: dataCenter, userToken: userToken, request: QueueEndpoint.getUserQueue, completionHandler: { response in
                switch response {
                case .success(let (data, response)):
                    self.updatePollingInterval(headers: response.allHeaderFields)
                    switch response.statusCode {
                    case 304:
                        guard let lastCachedResponse = self.cachedFetchUserQueueResponse else {
                            return completionHandler(.success(nil))
                        }

                        do {
                            let userQueue = try self.parseResponseBody(lastCachedResponse)

                            self.threadUtil.runMain {
                                completionHandler(.success(userQueue))
                            }
                        } catch {
                            completionHandler(.failure(error))
                        }
                    default:
                        do {
                            let userQueue = try self.parseResponseBody(data)

                            self.cachedFetchUserQueueResponse = data

                            self.threadUtil.runMain {
                                completionHandler(.success(userQueue))
                            }
                        } catch {
                            completionHandler(.failure(error))
                        }
                    }
                case .failure(let error):
                    completionHandler(.failure(error))
                }
            })
        } catch {
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
        if let newPollingIntervalString = headers["x-gist-queue-polling-interval"] as? String,
           let newPollingInterval = Double(newPollingIntervalString),
           newPollingInterval != DIGraphShared.shared.messageQueueManager.getInterval() {
            DispatchQueue.main.async {
                DIGraphShared.shared.messageQueueManager.setInterval(newPollingInterval)
                DIGraphShared.shared.messageQueueManager.setup(skipQueueCheck: true)
                Logger.instance.info(message: "Polling interval changed to: \(newPollingInterval) seconds")
            }
        }
    }
}
