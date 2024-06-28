import CioInternalCommon
import Foundation

class LogManager {
    let siteId: String
    let dataCenter: String
    let gistQueueNetwork: GistQueueNetwork = DIGraphShared.shared.gistQueueNetwork

    init(siteId: String, dataCenter: String) {
        self.siteId = siteId
        self.dataCenter = dataCenter
    }

    func logView(message: Message, userToken: String?, completionHandler: @escaping (Result<Void, Error>) -> Void) {
        do {
            if let queueId = message.id, let userToken = userToken {
                try gistQueueNetwork.request(
                    siteId: siteId,
                    dataCenter: dataCenter,
                    userToken: userToken,
                    request: LogEndpoint.logUserMessageView(queueId: queueId),
                    completionHandler: { response in
                        switch response {
                        case .success(let (_, response)):
                            if response.statusCode == 200 {
                                completionHandler(.success(()))
                            } else {
                                completionHandler(.failure(GistNetworkError.requestFailed))
                            }
                        case .failure(let error):
                            completionHandler(.failure(error))
                        }
                    }
                )
            } else {
                try gistQueueNetwork.request(
                    siteId: siteId,
                    dataCenter: dataCenter,
                    userToken: nil,

                    request: LogEndpoint.logMessageView(messageId: message.templateId),
                    completionHandler: { response in
                        switch response {
                        case .success(let (_, response)):
                            if response.statusCode == 200 {
                                completionHandler(.success(()))
                            } else {
                                completionHandler(.failure(GistNetworkError.requestFailed))
                            }
                        case .failure(let error):
                            completionHandler(.failure(error))
                        }
                    }
                )
            }
        } catch {
            completionHandler(.failure(error))
        }
    }
}
