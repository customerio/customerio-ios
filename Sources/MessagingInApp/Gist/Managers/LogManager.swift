import CioInternalCommon
import Foundation

// sourcery: InjectRegisterShared = "LogManager"
class LogManager {
    let gistQueueNetwork: GistQueueNetwork

    init(gistQueueNetwork: GistQueueNetwork) {
        self.gistQueueNetwork = DIGraphShared.shared.gistQueueNetwork
    }

    func logView(state: InAppMessageState, message: Message, completionHandler: @escaping (Result<Void, Error>) -> Void) {
        do {
            if let queueId = message.queueId, let _ = state.userId {
                try gistQueueNetwork.request(
                    state: state,
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
                    state: state,
                    request: LogEndpoint.logMessageView(messageId: message.messageId),
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

    func updateInboxMessageOpened(state: InAppMessageState, queueId: String, opened: Bool, completionHandler: @escaping (Result<Void, Error>) -> Void) {
        do {
            try gistQueueNetwork.request(
                state: state,
                request: LogEndpoint.updateInboxMessageOpened(queueId: queueId, opened: opened),
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
        } catch {
            completionHandler(.failure(error))
        }
    }
}
