import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public typealias HttpHeaders = [String: String]

public protocol HttpClient: AutoMockable {
    func request(
        _ params: HttpRequestParams,
        onComplete: @escaping (Result<Data, HttpRequestError>) -> Void
    )
    func downloadFile(url: URL, fileType: DownloadFileType, onComplete: @escaping (URL?) -> Void)
    func cancel(finishTasks: Bool)
}

// sourcery: InjectRegister = "HttpClient"
public class CIOHttpClient: HttpClient {
    private let session: URLSession
    private let baseUrls: HttpBaseUrls
    private var httpRequestRunner: HttpRequestRunner
    private let jsonAdapter: JsonAdapter
    private var globalDataStore: GlobalDataStore
    private let logger: Logger
    private let retryPolicyTimer: SimpleTimer
    private let retryPolicy: HttpRetryPolicy

    init(
        siteId: SiteId,
        sdkCredentialsStore: SdkCredentialsStore,
        configStore: SdkConfigStore,
        jsonAdapter: JsonAdapter,
        httpRequestRunner: HttpRequestRunner,
        globalDataStore: GlobalDataStore,
        logger: Logger,
        timer: SimpleTimer,
        retryPolicy: HttpRetryPolicy
    ) {
        self.httpRequestRunner = httpRequestRunner
        self.session = Self.getSession(siteId: siteId, apiKey: sdkCredentialsStore.credentials.apiKey)
        self.baseUrls = configStore.config.httpBaseUrls
        self.jsonAdapter = jsonAdapter
        self.globalDataStore = globalDataStore
        self.logger = logger
        self.retryPolicyTimer = timer
        self.retryPolicy = retryPolicy
    }

    deinit {
        self.cancel(finishTasks: true)
    }

    public func downloadFile(url: URL, fileType: DownloadFileType, onComplete: @escaping (URL?) -> Void) {
        httpRequestRunner.downloadFile(url: url, fileType: fileType, session: session, onComplete: onComplete)
    }

    public func request(_ params: HttpRequestParams, onComplete: @escaping (Result<Data, HttpRequestError>) -> Void) {
        if let httpPauseEnds = globalDataStore.httpRequestsPauseEnds, !httpPauseEnds.hasPassed {
            logger.debug("HTTP request ignored because requests are still paused.")
            return onComplete(.failure(.noRequestMade(nil)))
        }

        httpRequestRunner
            .request(params, httpBaseUrls: baseUrls, session: session) { [weak self] data, response, error in
                guard let self = self else { return }

                if let error = error {
                    if let error = self.isUrlError(error) {
                        return onComplete(.failure(error))
                    }

                    return onComplete(.failure(.noRequestMade(error)))
                }

                guard let response = response else {
                    return onComplete(.failure(.noRequestMade(nil)))
                }

                let statusCode = response.statusCode
                guard statusCode < 300 else {
                    return self.handleUnsuccessfulStatusCodeResponse(statusCode: statusCode, data: data, params: params,
                                                                     onComplete: onComplete)
                }

                guard let data = data else {
                    return onComplete(.failure(.noRequestMade(nil)))
                }

                onComplete(.success(data))
            }
    }

    private func getErrorMessage(responseBody: Data?) -> String? {
        guard let data = responseBody else {
            return nil
        }

        var errorBodyString: String? = data.string

        // don't log errors for JSON mapping since we are trying to decode *multiple* error classes.
        // we are bound to fail more often and don't want to log errors that are not super helpful to us.
        if let errorMessageBody: ErrorMessageResponse = jsonAdapter.fromJson(data,
                                                                             decoder: nil,
                                                                             logErrors: false) {
            errorBodyString = errorMessageBody.meta.error
        } else if let errorMessageBody: ErrorsMessageResponse = jsonAdapter.fromJson(data,
                                                                                     decoder: nil,
                                                                                     logErrors: false) {
            errorBodyString = errorMessageBody.meta.errors.joined(separator: ",")
        }
        return errorBodyString
    }

    public func cancel(finishTasks: Bool) {
        if finishTasks {
            session.finishTasksAndInvalidate()
        } else {
            session.invalidateAndCancel()
        }
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
}

extension CIOHttpClient {
    static func getSession(siteId: String, apiKey: String) -> URLSession {
        let urlSessionConfig = URLSessionConfiguration.ephemeral
        let basicAuthHeaderString = "Basic \(getBasicAuthHeaderString(siteId: siteId, apiKey: apiKey))"

        urlSessionConfig.allowsCellularAccess = true
        urlSessionConfig.timeoutIntervalForResource = 30
        urlSessionConfig.timeoutIntervalForRequest = 60
        urlSessionConfig.httpAdditionalHeaders = ["Content-Type": "application/json; charset=utf-8",
                                                  "Authorization": basicAuthHeaderString,
                                                  "User-Agent": getUserAgent()]

        return URLSession(configuration: urlSessionConfig, delegate: nil, delegateQueue: nil)
    }

    static func getBasicAuthHeaderString(siteId: String, apiKey: String) -> String {
        let rawHeader = "\(siteId):\(apiKey)"
        let encodedRawHeader = rawHeader.data(using: .utf8)!

        return encodedRawHeader.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0))
    }

    /**
     * getUserAgent - To get `user-agent` header value. This value depends on SDK version
     * and device detail such as OS version, device model, customer's app name etc
     *
     * In case, UIKit is available then this function returns value in following format :
     * `Customer.io iOS Client/1.0.0-alpha.16 (iPhone 11 Pro; iOS 14.5) User App/1.0`
     *
     * Otherwise will return
     * `Customer.io iOS Client/1.0.0-alpha.16`
     */
    static func getUserAgent() -> String {
        var userAgent = "Customer.io iOS Client/"
        userAgent += SdkVersion.version
        #if canImport(UIKit)
        userAgent += " (\(DeviceInfo.deviceInfo); \(DeviceInfo.osInfo))"
        userAgent += " \(DeviceInfo.customerAppName)/"
        userAgent += DeviceInfo.customerAppVersion
        #endif
        return userAgent
    }

    // In certain scenarios, it makes sense for us to pause making any HTTP requests to the
    // Customer.io API. Because HTTP requests are performed by the background queue, there is
    // a chance that the background queue could make a lot or more HTTP requests in
    // a short amount of time from a device which makes a performance impact on our API.
    // By pausing HTTP requests, we mitigate the chance of customer devices causing harm to our API.
    private func pauseHttpRequests() {
        // We do *not* want to make this value configurable by the customer because
        // we are pausing the SDK to protect our own API from spamming results.
        let minutesToPause = 5
        let dateToEndPause = Date().addMinutes(minutesToPause)

        globalDataStore.httpRequestsPauseEnds = dateToEndPause

        logger.info("All HTTP requests to the Customer.io API have been paused for \(minutesToPause) minutes.")
    }

    /**
     - When receiving a 5xx response:
     * Begin an exponential backoff retry on the HTTP task that returned back the 5xx error.
     * After these retry attempts, if the HTTP request is still receiving a 5xx response then the
       requests will sleep for 5 minutes and no requests will be attempted.
     * After the 5 minutes, HTTP requests are able to be run as normal. No memory of any errors prior.

     - When receiving a 401 response:
     * The HTTP requests will sleep for 5 minutes as above.

     - Any other 4xx error
     * Log the error as it's more then likely a SDK developer error or an error by the customer.
     */
    private func handleUnsuccessfulStatusCodeResponse(
        statusCode: Int,
        data: Data?,
        params: HttpRequestParams,
        onComplete: @escaping (Result<Data, HttpRequestError>) -> Void
    ) {
        let unsuccessfulStatusCodeError: HttpRequestError =
            .unsuccessfulStatusCode(statusCode,
                                    apiMessage: getErrorMessage(responseBody: data))

        switch statusCode {
        case 500 ..< 600:
            if let sleepTime = retryPolicy.nextSleepTime {
                logger
                    .debug("""
                    Encountered \(statusCode) HTTP response.
                    Sleeping \(sleepTime) seconds and then retrying.
                    """)

                retryPolicyTimer.scheduleAndCancelPrevious(seconds: sleepTime) {
                    self.request(params, onComplete: onComplete)
                }
            } else {
                pauseHttpRequests()

                onComplete(.failure(unsuccessfulStatusCodeError))
            }
        case 401:
            pauseHttpRequests()

            onComplete(.failure(.unauthorized))
        default:
            logger.error("""
            4xx HTTP status code response.
            Probably a bug? \(unsuccessfulStatusCodeError.localizedDescription)
            """)

            onComplete(.failure(unsuccessfulStatusCodeError))
        }
    }
}
