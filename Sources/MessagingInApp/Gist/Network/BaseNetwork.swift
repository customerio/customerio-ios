import Foundation

typealias GistNetworkResponse = (Data, HTTPURLResponse)

enum GistNetworkError: Error {
    case serverError
    case requestFailed
}

enum BaseNetwork {
    private static let sessionIdParameterName = "sessionId"

    static func request(
        _ request: GistNetworkRequest,
        urlRequest: URLRequest,
        baseURL: URL,
        completionHandler: @escaping (Result<GistNetworkResponse, Error>) -> Void
    ) throws {
        var urlRequest = urlRequest
        urlRequest.cachePolicy = .reloadIgnoringCacheData

        var components = URLComponents(string: baseURL.appendingPathComponent(request.path).absoluteString)

        // Always add sessionId as a query parameter
        var queryItems = [URLQueryItem(name: sessionIdParameterName, value: SessionManager.shared.sessionId)]
        switch request.parameters {
        case .body(let body):
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body.asDictionary(), options: [])
        case .id(let id):
            components = URLComponents(string: baseURL
                .appendingPathComponent(request.path)
                .appendingPathComponent(id).absoluteString
            )

        case .none:
            break
        }

        // Apply query parameters
        components?.queryItems = queryItems
        urlRequest.url = components?.url

        URLSession.shared.dataTask(with: urlRequest, completionHandler: { data, response, error in
            if let error = error { completionHandler(.failure(error)) }
            guard let data = data, let response = response as? HTTPURLResponse,
                  (200 ... 304).contains(response.statusCode)
            else {
                completionHandler(.failure(GistNetworkError.serverError))
                return
            }
            completionHandler(.success(GistNetworkResponse(data, response)))
        }).resume()
    }
}
