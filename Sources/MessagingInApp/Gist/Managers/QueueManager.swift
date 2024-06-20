import CioInternalCommon
import Foundation

class QueueManager {
    let siteId: String
    let dataCenter: String
    var globalDataStore: GlobalDataStore = DIGraphShared.shared.globalDataStore
    let gistQueueNetwork: GistQueueNetwork = DIGraphShared.shared.gistQueueNetwork

    init(siteId: String, dataCenter: String) {
        self.siteId = siteId
        self.dataCenter = dataCenter
    }

    func fetchUserQueue(userToken: String, completionHandler: @escaping (Result<[UserQueueResponse]?, Error>) -> Void) {
        do {
            try gistQueueNetwork.request(siteId: siteId, dataCenter: dataCenter, userToken: userToken, request: QueueEndpoint.getUserQueue, completionHandler: { [weak self] response in
                guard let self = self else { return }

                switch response {
                case .success(let (data, response)):
                    self.updatePollingInterval(headers: response.allHeaderFields)
                    switch response.statusCode {
                    case 204:
                        self.globalDataStore.inAppUserQueueFetchCachedResponse = nil
                        completionHandler(.success([]))
                    case 304:
                        guard let lastCachedResponse = self.globalDataStore.inAppUserQueueFetchCachedResponse else {
                            return completionHandler(.success(nil))
                        }

                        do {
                            let userQueue = try self.parseResponseBody(lastCachedResponse)

                            DispatchQueue.main.async {
                                completionHandler(.success(userQueue))
                            }
                        } catch {
                            completionHandler(.failure(error))
                        }
                    default:
                        do {
                            let userQueue = try self.parseResponseBody(data)

                            self.globalDataStore.inAppUserQueueFetchCachedResponse = data

                            DispatchQueue.main.async {
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
        var userQueue = [UserQueueResponse]()
        if let userQueueResponse =
            try JSONSerialization.jsonObject(
                with: responseBody,
                options: .allowFragments
            ) as? [[String: Any?]] {
            userQueueResponse.forEach { item in
                if let userQueueItem = UserQueueResponse(dictionary: item) {
                    userQueue.append(userQueueItem)
                }
            }
        }

        return userQueue
    }

    private func updatePollingInterval(headers: [AnyHashable: Any]) {
        if let newPollingIntervalString = headers["x-gist-queue-polling-interval"] as? String,
           let newPollingInterval = Double(newPollingIntervalString),
           newPollingInterval != Gist.shared.messageQueueManager.interval {
            DispatchQueue.main.async {
                Gist.shared.messageQueueManager.interval = newPollingInterval
                Gist.shared.messageQueueManager.setup(skipQueueCheck: true)
                Logger.instance.info(message: "Polling interval changed to: \(newPollingInterval) seconds")
            }
        }
    }
}
