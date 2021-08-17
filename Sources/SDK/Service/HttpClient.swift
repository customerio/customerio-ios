import Foundation

typealias HttpHeaders = [String: String]

internal protocol HttpClient: AutoMockable {
    func request(_ endpoint: HttpEndpoint, headers: HttpHeaders?, body: Data?, onComplete: @escaping (Result<Data, HttpRequestError>) -> Void)
}

internal class CIOHttpClient: HttpClient {
    private let session: URLSession
    private let region: Region
    private var httpRequestRunner: HttpRequestRunner

    /// for testing
    init(httpRequestRunner: HttpRequestRunner, region: Region) {
        self.httpRequestRunner = httpRequestRunner
        self.session = Self.getSession(siteId: "fake-site-id", apiKey: "fake-api-key")
        self.region = region
    }

    init(config: SdkConfig) {
        self.session = Self.getSession(siteId: config.siteId, apiKey: config.apiKey)
        self.region = config.region
        self.httpRequestRunner = UrlRequestHttpRequestRunner(session: session)
    }

    deinit {
        self.session.finishTasksAndInvalidate()
    }

    func request(_ endpoint: HttpEndpoint, headers: HttpHeaders?, body: Data?, onComplete: @escaping (Result<Data, HttpRequestError>) -> Void) {
        guard let url = httpRequestRunner.getUrl(endpoint: endpoint, region: region) else {
            onComplete(Result.failure(HttpRequestError.UrlConstruction(url: endpoint.getUrlString(region))))
            return
        }

        let requestParams = RequestParams(method: endpoint.method, url: url, headers: headers, body: body)

        httpRequestRunner.request(requestParams) { data, response, error in
            if let error = error {
                onComplete(Result.failure(HttpRequestError.UnderlyingError(error: error)))
                return
            }

            guard let response = response else {
                onComplete(Result.failure(HttpRequestError.NoResponse))
                return
            }

            let statusCode = response.statusCode
            guard statusCode < 300 else {
                switch statusCode {
                case 401:
                    onComplete(Result.failure(HttpRequestError.Unauthorized))
                default:
                    onComplete(Result.failure(HttpRequestError.UnsuccessfulStatusCode(code: statusCode)))
                }

                return
            }

            guard let data = data else {
                onComplete(Result.failure(HttpRequestError.NoResponse))
                return
            }

            onComplete(Result.success(data))
        }
    }
}

extension CIOHttpClient {
    static func getSession(siteId: String, apiKey: String) -> URLSession {
        let urlSessionConfig = URLSessionConfiguration.ephemeral

        urlSessionConfig.allowsCellularAccess = true
        urlSessionConfig.timeoutIntervalForResource = 30
        urlSessionConfig.timeoutIntervalForRequest = 60
        urlSessionConfig.httpAdditionalHeaders = ["Content-Type": "application/json; charset=utf-8",
                                                  "Authorization": "Basic \(getBasicAuthHeaderString(siteId: siteId, apiKey: apiKey))",
                                                  "User-Agent": "CustomerIO-SDK-iOS-/\(SdkVersion.version)"]

        return URLSession(configuration: urlSessionConfig, delegate: nil, delegateQueue: nil)
    }

    static func getBasicAuthHeaderString(siteId: String, apiKey: String) -> String {
        let rawHeader = "\(siteId):\(apiKey)"
        let encodedRawHeader = rawHeader.data(using: .utf8)!

        return encodedRawHeader.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0))
    }
}
