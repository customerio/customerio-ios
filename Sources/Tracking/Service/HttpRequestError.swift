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
    case unsuccessfulStatusCode(_ code: Int, message: String)
    /// Request was not able to get a response from server. Maybe no network connection?
    case noResponse(_ urlError: URLError?)
    /// An error happened to prevent the request from happening. Check the `description` to get the underlying error.
    case underlyingError(_ error: Error)
}

extension HttpRequestError: CustomStringConvertible, LocalizedError {
    /// Custom description for the Error to describe the error that happened.
    public var description: String {
        switch self {
        case .unauthorized: return "HTTP request responded with 401. Configure the SDK with valid credentials."
        case .urlConstruction(let url): return "HTTP URL not a valid URL: \(url)"
        case .unsuccessfulStatusCode(let code, let message):
            return "Response received, but status code = \(String(code)). \(message)"
        case .noResponse(let urlError): return urlError?.localizedDescription ?? "No response was returned from server."
        case .underlyingError(let error): return error.localizedDescription
        }
    }
}
