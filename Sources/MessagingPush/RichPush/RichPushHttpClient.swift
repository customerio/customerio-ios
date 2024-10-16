import CioInternalCommon
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// sourcery: InjectRegisterShared = "HttpClient"
public class RichPushHttpClient: HttpClient {
    private let httpRequestRunner: HttpRequestRunner
    private let jsonAdapter: JsonAdapter
    private let logger: Logger
    private let cioApiSession: URLSession // only used to call the CIO API.
    private let publicSession: URLSession // session used to call servers accessible to the public (such as CDNs)
    private var allSessions: [URLSession] {
        [cioApiSession, publicSession]
    }

    public func request(_ params: CioInternalCommon.HttpRequestParams, onComplete: @escaping (Result<Data, CioInternalCommon.HttpRequestError>) -> Void) {
        httpRequestRunner
            .request(
                params: params,
                session: getSessionForRequest(url: params.url)
            ) { [weak self] data, response, error in
                guard let self = self else { return }

                if let error = error {
                    logger.error("Error sending request \(error.localizedDescription).")
                    if let error = self.isUrlError(error) {
                        return onComplete(.failure(error))
                    }

                    return onComplete(.failure(.noRequestMade(error)))
                } else if let httpResponse = response {
                    if httpResponse.statusCode < 300 {
                        guard let data = data else {
                            return onComplete(.failure(.noRequestMade(nil)))
                        }

                        onComplete(.success(data))
                    } else {
                        logger.error("""
                        \(httpResponse.statusCode) HTTP status code response.
                        Error description: \(httpResponse.description)
                        """)

                        let unsuccessfulStatusCodeError: HttpRequestError =
                            .unsuccessfulStatusCode(
                                httpResponse.statusCode,
                                apiMessage: getErrorMessageFromServerResponse(responseBody: data)
                            )
                        onComplete(.failure(unsuccessfulStatusCodeError))
                    }
                } else {
                    onComplete(.failure(.noRequestMade(nil)))
                }
            }
    }

    func getSessionForRequest(url: URL) -> URLSession {
        let cioApiHostname = URL(string: Self.defaultAPIHost)!.host
        let requestHostname = url.host
        let isRequestToCIOApi = cioApiHostname == requestHostname

        return isRequestToCIOApi ? cioApiSession : publicSession
    }

    private func getErrorMessageFromServerResponse(responseBody: Data?) -> String {
        guard let data = responseBody, var errorBodyString = data.string else {
            return "(server did not give a response)"
        }

        // don't log errors for JSON mapping since we are trying to decode *multiple* error classes.
        // we are bound to fail more often and don't want to log errors that are not super helpful to us.
        if let errorMessageBody: ErrorMessageResponse = jsonAdapter.fromJson(
            data,
            logErrors: false
        ) {
            errorBodyString = errorMessageBody.meta.error
        } else if let errorMessageBody: ErrorsMessageResponse = jsonAdapter.fromJson(
            data,
            logErrors: false
        ) {
            errorBodyString = errorMessageBody.meta.errors.joined(separator: ",")
        }
        return errorBodyString
    }

    private func isUrlError(_ error: Error) -> HttpRequestError? {
        guard let urlError = error as? URLError else { return nil }

        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut:
            return .noOrBadNetwork(urlError)
        case .cancelled:
            return .cancelled
        default: return nil
        }
    }

    public func downloadFile(url: URL, fileType: DownloadFileType, onComplete: @escaping (URL?) -> Void) {
        httpRequestRunner.downloadFile(
            url: url,
            fileType: fileType,
            session: getSessionForRequest(url: url),
            onComplete: onComplete
        )
    }

    public func cancel(finishTasks: Bool) {
        if finishTasks {
            allSessions.forEach { $0.finishTasksAndInvalidate() }
        } else {
            allSessions.forEach { $0.invalidateAndCancel() }
        }
    }

    init(
        jsonAdapter: JsonAdapter,
        httpRequestRunner: HttpRequestRunner,
        logger: Logger,
        userAgentUtil: UserAgentUtil
    ) {
        self.httpRequestRunner = httpRequestRunner
        self.jsonAdapter = jsonAdapter
        self.logger = logger

        self.publicSession = Self.getBasicSession()
        self.cioApiSession = Self.getCIOApiSession(
            key: MessagingPush.moduleConfig.cdpApiKey,
            userAgentHeaderValue: userAgentUtil.getNSEUserAgentHeaderValue()
        )
    }

    deinit {
        self.cancel(finishTasks: true)
    }
}

extension RichPushHttpClient {
    public static let defaultAPIHost = "https://cdp.customer.io/v1"

    static func authorizationHeaderForCdpApiKey(_ key: String) -> String {
        var returnHeader = "\(key):"
        if let encodedRawHeader = returnHeader.data(using: .utf8) {
            returnHeader = encodedRawHeader.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0))
        }
        return returnHeader
    }

    static func getCIOsessionHeader(
        cdpApiKey: String,
        userAgentHeaderValue: String
    ) -> [String: String] {
        let basicAuthHeaderString = "Basic \(authorizationHeaderForCdpApiKey(cdpApiKey))"

        return ["Content-Type": "application/json; charset=utf-8",
                "User-Agent": userAgentHeaderValue,
                "Authorization": basicAuthHeaderString]
    }

    static func getBasicSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.allowsCellularAccess = true
        configuration.timeoutIntervalForResource = 30
        configuration.timeoutIntervalForRequest = 60
        configuration.httpAdditionalHeaders = [:]
        let session = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
        return session
    }

    static func getCIOApiSession(key: String, userAgentHeaderValue: String) -> URLSession {
        let urlSessionConfig = getBasicSession().configuration

        urlSessionConfig.httpAdditionalHeaders = getCIOsessionHeader(cdpApiKey: key, userAgentHeaderValue: userAgentHeaderValue)

        return URLSession(configuration: urlSessionConfig, delegate: nil, delegateQueue: nil)
    }
}
