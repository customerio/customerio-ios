import Foundation

/**
 Errors that can happen during an HTTP request.
 */
public enum HttpRequestError: Error {
    /// 401 status code. Probably need to re-configure SDK with valid credentials.
    case Unauthorized
    /// HTTP URL for the request not a valid URL.
    case UrlConstruction(url: String)
    /// A response came back, but status code > 300 and not handled already (example: 401)
    case UnsuccessfulStatusCode(code: Int)
    /// Request was not able to even make a request.
    case NoResponse
    /// An error happened to prevent the request from happening. Check the `description` to get the underlying error.
    case UnderlyingError(error: Error)
}

extension HttpRequestError: CustomStringConvertible {
    /// Custom description for the Error to describe the error that happened.
    public var description: String {
        switch self {
        case .Unauthorized: return "HTTP request responded with 401. It's recommended you configure SDK again with valid credentials."
        case .UrlConstruction(let url): return "HTTP URL not a valid URL: \(url)"
        case .UnsuccessfulStatusCode(let code): return "Response received, but status code > 300 (\(String(code)))"
        case .NoResponse: return "No response was returned from server."
        case .UnderlyingError(let error): return error.localizedDescription
        }
    }
}
