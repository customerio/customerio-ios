import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/**
 Exists to be able to mock http requests so we can test our HttpClient's response handling logic.
 */
internal protocol HttpRequestRunner: AutoMockable {
    func request(
        _ params: HttpRequestParams,
        httpBaseUrls: HttpBaseUrls,
        onComplete: @escaping (Data?, HTTPURLResponse?, Error?) -> Void
    )
}

internal class UrlRequestHttpRequestRunner: HttpRequestRunner {
    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    /**
     Note: When mocking request, open JSON file, convert to `Data`.
     */
    func request(
        _ params: HttpRequestParams,
        httpBaseUrls: HttpBaseUrls,
        onComplete: @escaping (Data?, HTTPURLResponse?, Error?) -> Void
    ) {
        guard let url = getUrl(endpoint: params.endpoint, baseUrls: httpBaseUrls) else {
            let error = HttpRequestError.urlConstruction(params.endpoint.getUrlString(baseUrls: httpBaseUrls))
            onComplete(nil, nil, error)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = params.endpoint.method
        request.httpBody = params.body
        params.headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        session.dataTask(with: request) { data, response, error in
            /**
             /// uncomment when running HTTP tests on local machine for debugging
             print("----------------- HTTP logs start -----------------")
             print("\(request.httpMethod) - \(request.url?.absoluteString)")
             print("Request body: \(request.httpBody?.string)")
             print(data?.string)
             print(error?.localizedDescription)
             print("----------------- HTTP logs end   -----------------")
             */

            onComplete(data, response as? HTTPURLResponse, error)
        }.resume()
    }

    private func getUrl(endpoint: HttpEndpoint, baseUrls: HttpBaseUrls) -> URL? {
        endpoint.getUrl(baseUrls: baseUrls)
    }
}
