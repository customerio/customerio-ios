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

    init(
        siteId: SiteId,
        sdkCredentialsStore: SdkCredentialsStore,
        configStore: SdkConfigStore,
        jsonAdapter: JsonAdapter,
        httpRequestRunner: HttpRequestRunner
    ) {
        self.httpRequestRunner = httpRequestRunner
        self.session = Self.getSession(siteId: siteId, apiKey: sdkCredentialsStore.credentials.apiKey)
        self.baseUrls = configStore.config.httpBaseUrls
        self.jsonAdapter = jsonAdapter
    }

    deinit {
        self.cancel(finishTasks: true)
    }

    public func downloadFile(url: URL, fileType: DownloadFileType, onComplete: @escaping (URL?) -> Void) {
        httpRequestRunner.downloadFile(url: url, fileType: fileType, session: session, onComplete: onComplete)
    }

    public func request(_ params: HttpRequestParams, onComplete: @escaping (Result<Data, HttpRequestError>) -> Void) {
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
                    switch statusCode {
                    case 401:
                        onComplete(.failure(.unauthorized))
                    default:
                        var errorBodyString: String = data?.string ?? ""
                        if let data = data,
                           let errorMessageBody: ErrorMessageResponse = self.jsonAdapter.fromJson(data) {
                            errorBodyString = errorMessageBody.meta.error
                        }

                        onComplete(.failure(.unsuccessfulStatusCode(statusCode, message: errorBodyString)))
                    }

                    return
                }

                guard let data = data else {
                    return onComplete(.failure(.noRequestMade(nil)))
                }

                onComplete(.success(data))
            }
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
                                                  "User-Agent": "CustomerIO-SDK-iOS/\(SdkVersion.version)"]

        return URLSession(configuration: urlSessionConfig, delegate: nil, delegateQueue: nil)
    }

    static func getBasicAuthHeaderString(siteId: String, apiKey: String) -> String {
        let rawHeader = "\(siteId):\(apiKey)"
        let encodedRawHeader = rawHeader.data(using: .utf8)!

        return encodedRawHeader.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0))
    }
}
