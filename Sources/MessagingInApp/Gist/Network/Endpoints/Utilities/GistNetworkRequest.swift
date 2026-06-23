import Foundation

protocol GistNetworkRequest {
    var method: HTTPMethod { get }
    var path: String { get }
    var parameters: RequestParameters? { get }
    /// Optional per-request timeout (seconds). When nil, URLSession's default timeout applies.
    var timeoutInterval: TimeInterval? { get }
}

extension GistNetworkRequest {
    var timeoutInterval: TimeInterval? { nil }
}

enum RequestParameters {
    case body(_: Encodable)
    case id(_: String)
    case idWithBody(id: String, body: Encodable)
}
