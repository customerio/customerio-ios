import Foundation

public struct HttpRequestParams {
    public let endpoint: HttpEndpoint
    public let headers: HttpHeaders?
    public let body: Data?

    /// swift's auto generated public init isn't accessible outside modules.
    public init(endpoint: HttpEndpoint, headers: HttpHeaders?, body: Data?) {
        self.endpoint = endpoint
        self.headers = headers
        self.body = body
    }
}
