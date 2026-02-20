import Foundation

enum LogEndpoint: GistNetworkRequest {
    case logUserMessageView(queueId: String)
    case logMessageView(messageId: String)
    case updateInboxMessageOpened(queueId: String, opened: Bool)

    var method: HTTPMethod {
        switch self {
        case .logUserMessageView:
            return .post
        case .logMessageView:
            return .post
        case .updateInboxMessageOpened:
            return .patch
        }
    }

    var parameters: RequestParameters? {
        switch self {
        case .logUserMessageView(let queueId):
            return .id(queueId)
        case .logMessageView(let messageId):
            return .id(messageId)
        case .updateInboxMessageOpened(let queueId, let opened):
            return .idWithBody(id: queueId, body: ["opened": opened])
        }
    }

    var path: String {
        switch self {
        case .logUserMessageView:
            return "/api/v1/logs/queue"
        case .logMessageView:
            return "/api/v1/logs/message"
        case .updateInboxMessageOpened:
            return "/api/v1/messages"
        }
    }
}
