import Foundation

internal protocol HttpErrorUtil: AutoMockable {
    func isIgnorable(_ error: Error) -> Bool
    func isHttpError(_ error: Error) -> HttpRequestError?
}

/// Error codes: https://developer.apple.com/documentation/foundation/urlerror/code
// sourcery: InjectRegister = "HttpErrorUtil"
internal class CioHttpErrorUtil: HttpErrorUtil {
    func isIgnorable(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return true
            default: break
            }
        }

        return false
    }

    func isHttpError(_ error: Error) -> HttpRequestError? {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return .noResponse(urlError)
            default: break
            }
        }

        return nil
    }
}
