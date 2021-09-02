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

    /// for testing
    init(httpRequestRunner: HttpRequestRunner, jsonAdapter: JsonAdapter) {
        self.httpRequestRunner = httpRequestRunner
        self.session = Self.getSession(siteId: "fake-site-id", apiKey: "fake-api-key")
        self.baseUrls = HttpBaseUrls(trackingApi: "fake-url")
        self.jsonAdapter = jsonAdapter
    }

    public init(credentials: SdkCredentials, config: SdkConfig) {
        self.session = Self.getSession(siteId: credentials.siteId, apiKey: credentials.apiKey)
        self.baseUrls = config.httpBaseUrls
        self.httpRequestRunner = UrlRequestHttpRequestRunner(session: session)
        self.jsonAdapter = DITracking.shared.jsonAdapter
    }

    deinit {
        self.session.finishTasksAndInvalidate()
    }

    public func request(_ params: HttpRequestParams, onComplete: @escaping (Result<Data, HttpRequestError>) -> Void) {
        httpRequestRunner.request(params, httpBaseUrls: baseUrls) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                onComplete(Result.failure(HttpRequestError.underlyingError(error)))
                return
            }

            guard let response = response else {
                onComplete(Result.failure(HttpRequestError.noResponse))
                return
            }

            let statusCode = response.statusCode
            guard statusCode < 300 else {
                switch statusCode {
                case 401:
                    onComplete(Result.failure(HttpRequestError.unauthorized))
                default:
                    var errorBodyString: String = data?.string ?? ""
                    if let data = data, let errorMessageBody: ErrorMessageResponse = self.jsonAdapter.fromJson(data) {
                        errorBodyString = errorMessageBody.meta.error
                    }

                    onComplete(Result
                        .failure(HttpRequestError.unsuccessfulStatusCode(statusCode, message: errorBodyString)))
                }

                return
            }

            guard let data = data else {
                onComplete(Result.failure(HttpRequestError.noResponse))
                return
            }

            onComplete(Result.success(data))
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
