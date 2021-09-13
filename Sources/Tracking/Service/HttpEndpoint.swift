import Foundation

public enum HttpEndpoint {
    case findAccountRegion
    case identifyCustomer(identifier: String)
    case registerDevice(identifier: String)
    case deleteDevice(identifier: String, deviceToken: Data)
    case trackCustomerEvent(identifier: String)
    case trackAnonymousEvent

    var path: String {
        switch self {
        case .findAccountRegion: return "/accounts/region"
        case .identifyCustomer(let identifier): return "/customers/\(identifier)"
        case .registerDevice(let identifier): return "/customers/\(identifier)/devices"
        case .deleteDevice(let identifier, let deviceToken): return "/customers/\(identifier)/devices/\(deviceToken)"
        case .trackCustomerEvent(let identifier): return "/customers/\(identifier)/events"
        case .trackAnonymousEvent: return "/events"
        }
    }

    var method: String {
        switch self {
        case .findAccountRegion: return "GET"
        case .identifyCustomer: return "PUT"
        case .registerDevice: return "PUT"
        case .deleteDevice: return "DELETE"
        case .trackCustomerEvent: return "POST"
        case .trackAnonymousEvent: return "POST"
        }
    }
}

public extension HttpEndpoint {
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
public struct HttpBaseUrls: Equatable {
    let trackingApi: String

    static func getProduction(region: Region) -> HttpBaseUrls {
        HttpBaseUrls(trackingApi: region.productionTrackingUrl)
    }
}
