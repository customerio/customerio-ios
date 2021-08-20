import Foundation

public enum SdkError: Error {
    /// SDK has not been initialized yet. Check the docs for `CustomerIO` class.
    case notInitialized
}

extension SdkError: CustomStringConvertible {
    /// Custom description for the Error to describe the error that happened.
    public var description: String {
        switch self {
        case .notInitialized: return "SDK has not been initialized yet. Check the docs for CustomerIO class."
        }
    }
}
