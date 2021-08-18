import Foundation

internal enum HttpEndpoint {
    case findAccountRegion
    case identifyCustomer(identifier: String)

    var path: String {
        switch self {
        case .findAccountRegion: return "/accounts/region"
        case .identifyCustomer(let identifier): return "/customers/\(identifier)"
        }
    }

    var method: String {
        switch self {
        case .findAccountRegion: return "GET"
        case .identifyCustomer: return "PUT"
        }
    }
}

internal extension HttpEndpoint {
    func getUrl(baseUrls: HttpBaseUrls) -> URL? {
        URL(string: getUrlString(baseUrls: baseUrls))
    }

    func getUrlString(baseUrls: HttpBaseUrls) -> String {
        // At this time, all endpoints use tracking endpoint so we only use only 1 base URL here.
        var baseUrl = baseUrls.trackingApi

        guard !baseUrl.isEmpty else {
            return ""
        }
        if baseUrl.last! == "/" {
            baseUrl = String(baseUrl.dropLast())
        }

        return baseUrl + path
    }
}

/**
 Collection of the different base URLs for all the APIs of Customer.io.
 Each endpoint in `HttpEndpoint` knows what base API that it needs. That is where
 the full URL including path is constructed.
 */
internal struct HttpBaseUrls: Equatable {
    let trackingApi: String
}
