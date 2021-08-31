import Foundation

/**
 Top level error type of the Customer.io SDK.
 Any error that occurs in the SDK is a `CustomerIOError` so that you can
 parse the `Error` to find out more about it.

 ```
 switch error {
 case .notInitialized:
   //
   break
 case .httpError(let httpError):
   switch httpError {
   ...
   }
   break
 }
 ```
 */
public enum CustomerIOError: Error {
    /// SDK has not been initialized yet. Check the docs for `CustomerIO` class.
    case notInitialized
    /// Device has not been registered yet.
    case deviceNotRegistered
    /// Customer has not yet been identified
    case noCustomerIdentified
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
        case .deviceNotRegistered: return "Device token has not been registered."
        case .noCustomerIdentified: return "Customer has not yet been identified."
        case .httpError(let error): return error.description
        case .underlyingError(let error): return error.localizedDescription
        }
    }
}
