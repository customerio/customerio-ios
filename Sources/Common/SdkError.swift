import Foundation

public enum CustomerIOError: Error {
    /// SDK has not been initialized yet. Check the docs for `CustomerIO` class.
    case notInitialized
    /// Error occurred while performing a HTTP request. Parse the embedded error.
    case httpError(_ error: HttpRequestError)
    /// An error occurred. That's all that we know. Check the embedded error to learn more.
    case underlyingError(_ error: Error)
}

extension CustomerIOError: CustomStringConvertible, LocalizedError {
    /// Custom description for the Error to describe the error that happened.
    public var description: String {
        switch self {
        case .notInitialized: return "SDK has not been initialized yet. Check the docs about initializing the SDK."
        case .httpError(let error): return error.description
        case .underlyingError(let error): return error.localizedDescription
        }
    }
}
