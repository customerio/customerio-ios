import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/**
 Exists to be able to mock http requests so we can test our HttpClient's response handling logic.
 */
internal protocol HttpRequestRunner: AutoMockable {
    func getUrl(endpoint: HttpEndpoint, baseUrls: HttpBaseUrls) -> URL?
    func request(_ params: RequestParams, _ onComplete: @escaping (Data?, HTTPURLResponse?, Error?) -> Void)
}

internal class UrlRequestHttpRequestRunner: HttpRequestRunner {
    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    func getUrl(endpoint: HttpEndpoint, baseUrls: HttpBaseUrls) -> URL? {
        endpoint.getUrl(baseUrls: baseUrls)
    }

    func request(_ params: RequestParams, _ onComplete: @escaping (Data?, HTTPURLResponse?, Error?) -> Void) {
        var request = URLRequest(url: params.url)
        request.httpMethod = params.method
        request.httpBody = params.body
        params.headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        session.dataTask(with: request) { data, response, error in
            onComplete(data, response as? HTTPURLResponse, error)
        }.resume()
    }
}

/**
 Using struct to avoid having a request function with lots of parameters.
 This makes a request function easier to mock in tests.
 */
internal struct RequestParams {
    let method: String
    let url: URL
    let headers: HttpHeaders?
    let body: Data?
}
