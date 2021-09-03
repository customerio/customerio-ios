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
}

public class CIOHttpClient: HttpClient {
    private let session: URLSession
    private let baseUrls: HttpBaseUrls
    private var httpRequestRunner: HttpRequestRunner
    private let jsonAdapter: JsonAdapter
    private let httpErrorUtil: HttpErrorUtil

    /// for testing
    init(httpRequestRunner: HttpRequestRunner, jsonAdapter: JsonAdapter, httpErrorUtil: HttpErrorUtil) {
        self.httpRequestRunner = httpRequestRunner
        self.session = Self.getSession(siteId: "fake-site-id", apiKey: "fake-api-key")
        self.baseUrls = HttpBaseUrls(trackingApi: "fake-url")
        self.jsonAdapter = jsonAdapter
        self.httpErrorUtil = httpErrorUtil
    }

    public init(credentials: SdkCredentials, config: SdkConfig) {
        self.session = Self.getSession(siteId: credentials.siteId, apiKey: credentials.apiKey)
        self.baseUrls = config.httpBaseUrls
        self.httpRequestRunner = UrlRequestHttpRequestRunner(session: session)
        self.jsonAdapter = DITracking.shared.jsonAdapter
        self.httpErrorUtil = DITracking.shared.httpErrorUtil
    }

    deinit {
        self.session.finishTasksAndInvalidate()
    }

    public func request(_ params: HttpRequestParams, onComplete: @escaping (Result<Data, HttpRequestError>) -> Void) {
        httpRequestRunner.request(params, httpBaseUrls: baseUrls) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                if self.httpErrorUtil.isIgnorable(error) {
                    return // do not call onComplete() because the error is ignorable
                }
                if let error = self.httpErrorUtil.isHttpError(error) {
                    return onComplete(.failure(error))
                }

                return onComplete(.failure(.underlyingError(error)))
            }

            guard let response = response else {
                return onComplete(.failure(.noResponse(nil)))
            }

            let statusCode = response.statusCode
            guard statusCode < 300 else {
                switch statusCode {
                case 401:
                    onComplete(.failure(.unauthorized))
                default:
                    var errorBodyString: String = data?.string ?? ""
                    if let data = data, let errorMessageBody: ErrorMessageResponse = self.jsonAdapter.fromJson(data) {
                        errorBodyString = errorMessageBody.meta.error
                    }

                    onComplete(.failure(.unsuccessfulStatusCode(statusCode, message: errorBodyString)))
                }

                return
            }

            guard let data = data else {
                return onComplete(.failure(.noResponse(nil)))
            }

            onComplete(.success(data))
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
