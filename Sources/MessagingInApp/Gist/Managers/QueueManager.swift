import CioInternalCommon
import Foundation

class QueueManager {
    let siteId: String
    let dataCenter: String
    var globalDataStore: GlobalDataStore = DIGraphShared.shared.globalDataStore

    init(siteId: String, dataCenter: String) {
        self.siteId = siteId
        self.dataCenter = dataCenter
    }

    func fetchUserQueue(userToken: String, completionHandler: @escaping (Result<[UserQueueResponse]?, Error>) -> Void) {
        do {
            try GistQueueNetwork(siteId: siteId, dataCenter: dataCenter, userToken: userToken)
                .request(QueueEndpoint.getUserQueue, completionHandler: { [weak self] response in
                    guard let self = self else { return }

                    switch response {
                    case .success(let (data, response)):
                        self.updatePollingInterval(headers: response.allHeaderFields)
                        switch response.statusCode {
                        case 204:
                            self.globalDataStore.inAppUserQueueFetchCachedResponse = nil
                            completionHandler(.success([]))
                        default:
                            var httpResponseBody = data

                            if response.statusCode == 304, let lastCachedResponse = self.globalDataStore.inAppUserQueueFetchCachedResponse {
                                httpResponseBody = lastCachedResponse
                            } else {
                                self.globalDataStore.inAppUserQueueFetchCachedResponse = httpResponseBody
                            }

                            do {
                                var userQueue = [UserQueueResponse]()
                                if let userQueueResponse =
                                    try JSONSerialization.jsonObject(
                                        with: httpResponseBody,
                                        options: .allowFragments
                                    ) as? [[String: Any?]] {
                                    userQueueResponse.forEach { item in
                                        if let userQueueItem = UserQueueResponse(dictionary: item) {
                                            userQueue.append(userQueueItem)
                                        }
                                    }
                                }
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
