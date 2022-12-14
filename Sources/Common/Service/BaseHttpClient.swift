import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/**
 Common functions used by all HTTP clients in project.
 */
open class BaseHttpClient {
    public let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    public func cancel(finishTasks: Bool) {
        if finishTasks {
            session.finishTasksAndInvalidate()
        } else {
            session.invalidateAndCancel()
        }
    }

    public func isUrlError(_ error: Error) -> HttpRequestError? {
        guard let urlError = error as? URLError else { return nil }

        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut:
            return .noOrBadNetwork(urlError)
        case .cancelled:
            return .cancelled
        default: return nil
        }
    }

    static func getBasicSession() -> URLSession {
        let urlSessionConfig = URLSessionConfiguration.ephemeral

        urlSessionConfig.allowsCellularAccess = true
        urlSessionConfig.timeoutIntervalForResource = 30
        urlSessionConfig.timeoutIntervalForRequest = 60

        return URLSession(configuration: urlSessionConfig, delegate: nil, delegateQueue: nil)
    }
}
