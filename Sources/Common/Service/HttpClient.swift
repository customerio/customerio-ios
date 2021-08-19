import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

typealias HttpHeaders = [String: String]

internal protocol HttpClient: AutoMockable {
    func request(
        _ endpoint: HttpEndpoint,
        headers: HttpHeaders?,
        body: Data?,
        onComplete: @escaping (Result<Data, HttpRequestError>) -> Void
    )
}

internal class CIOHttpClient: HttpClient {
    private let session: URLSession
    private let baseUrls: HttpBaseUrls
    private var httpRequestRunner: HttpRequestRunner

    /// for testing
    init(httpRequestRunner: HttpRequestRunner) {
        self.httpRequestRunner = httpRequestRunner
        self.session = Self.getSession(siteId: "fake-site-id", apiKey: "fake-api-key")
        self.baseUrls = HttpBaseUrls(trackingApi: "fake-url")
    }

    init(credentials: SdkCredentials, config: SdkConfig) {
        self.session = Self.getSession(siteId: credentials.siteId, apiKey: credentials.apiKey)
        self.baseUrls = config.httpBaseUrls
        self.httpRequestRunner = UrlRequestHttpRequestRunner(session: session)
    }

    deinit {
        self.session.finishTasksAndInvalidate()
    }

    func request(
        _ endpoint: HttpEndpoint,
        headers: HttpHeaders?,
        body: Data?,
        onComplete: @escaping (Result<Data, HttpRequestError>) -> Void
    ) {
        guard let url = httpRequestRunner.getUrl(endpoint: endpoint, baseUrls: baseUrls) else {
            onComplete(Result.failure(HttpRequestError.urlConstruction(endpoint.getUrlString(baseUrls: baseUrls))))
            return
        }

        let requestParams = RequestParams(method: endpoint.method, url: url, headers: headers, body: body)

        httpRequestRunner.request(requestParams) { data, response, error in
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
                    onComplete(Result.failure(HttpRequestError.unsuccessfulStatusCode(statusCode)))
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
                                                  "User-Agent": "CustomerIO-SDK-iOS-/\(SdkVersion.version)"]

        return URLSession(configuration: urlSessionConfig, delegate: nil, delegateQueue: nil)
    }

    static func getBasicAuthHeaderString(siteId: String, apiKey: String) -> String {
        let rawHeader = "\(siteId):\(apiKey)"
        let encodedRawHeader = rawHeader.data(using: .utf8)!

        return encodedRawHeader.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0))
    }
}
