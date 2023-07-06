import Foundation

// Parsed URL for more convenient deep link handling for customers.
// Pass this object to customers for them to handle deep links in their apps.
public struct DeepLink: Equatable {
    public let scheme: String
    public let host: String
    public let path: String?
    public let queryParameters: [String: String]
    public let url: URL

    public init?(deepLinkUrl: URL) {
        guard let urlComponents = URLComponents(url: deepLinkUrl, resolvingAgainstBaseURL: false),
              let scheme = urlComponents.scheme,
              let host = urlComponents.host
        else {
            return nil
        }

        self.url = deepLinkUrl
        self.scheme = scheme
        self.host = host
        self.path = urlComponents.path

        var queryParameters: [String: String] = [:]

        urlComponents.queryItems?.forEach {
            queryParameters[$0.name] = $0.value
        }

        self.queryParameters = queryParameters
    }
}
