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
    /// Error occurred while performing a HTTP request. Parse the embedded error.
    case http(_ error: HttpRequestError)
    /// An error occurred. That's all that we know. Check the embedded error to learn more.
    case underlying(_ error: Error)
}

extension CustomerIOError: CustomStringConvertible, LocalizedError {
    /// Custom description for the Error to describe the error that happened.
    public var description: String {
        switch self {
        case .notInitialized: return "SDK has not been initialized yet. Check the docs about initializing the SDK."
        case .http(let error): return error.description
        case .underlying(let error): return error.localizedDescription
        }
    }
}
