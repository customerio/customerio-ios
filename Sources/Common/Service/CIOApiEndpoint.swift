import Foundation

public enum CIOApiEndpoint {
    case trackPushMetricsCdp

    var path: String {
        switch self {
        case .trackPushMetricsCdp: return "/track"
        }
    }

    var method: String {
        switch self {
        case .trackPushMetricsCdp: return "POST"
        }
    }
}

public extension CIOApiEndpoint {
    func getUrl(baseUrl: String) -> URL? {
        URL(string: getUrlString(baseUrl: baseUrl))
    }

    func getUrlString(baseUrl: String) -> String {
        var baseUrl = baseUrl
        guard !baseUrl.isEmpty else {
            return ""
        }
        if baseUrl.last! == "/" {
            baseUrl = String(baseUrl.dropLast())
        }

        let fullPath = baseUrl + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)
        return fullPath
    }
}

/**
 Collection of the different base URLs for all the APIs of Customer.io.
 Each endpoint in `HttpEndpoint` knows what base API that it needs. That is where
 the full URL including path is constructed.
 */
public struct HttpBaseUrls: Equatable {
    let trackingApi: String

    static func getProduction(region: Region) -> HttpBaseUrls {
        HttpBaseUrls(trackingApi: region.productionTrackingUrl)
    }
}
