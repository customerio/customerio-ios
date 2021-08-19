import Foundation

/**
 Errors that can happen during an HTTP request.
 */
public enum HttpRequestError: Error {
    /// 401 status code. Probably need to re-configure SDK with valid credentials.
    case unauthorized
    /// HTTP URL for the request not a valid URL.
    case urlConstruction(_ url: String)
    /// A response came back, but status code > 300 and not handled already (example: 401)
    case unsuccessfulStatusCode(_ code: Int)
    /// Request was not able to even make a request.
    case noResponse
    /// An error happened to prevent the request from happening. Check the `description` to get the underlying error.
    case underlyingError(_ error: Error)
}

extension HttpRequestError: CustomStringConvertible {
    /// Custom description for the Error to describe the error that happened.
    public var description: String {
        switch self {
        case .unauthorized: return "HTTP request responded with 401. Configure the SDK with valid credentials."
        case .urlConstruction(let url): return "HTTP URL not a valid URL: \(url)"
        case .unsuccessfulStatusCode(let code): return "Response received, but status code > 300 (\(String(code)))"
        case .noResponse: return "No response was returned from server."
        case .underlyingError(let error): return error.localizedDescription
        }
    }
}
