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
    func getUrl(_ region: Region) -> URL? {
        // At this time, all endpoints use tracking endpoint so we only use only 1 base URL here.
        URL(string: getUrlString(region))
    }

    func getUrlString(_ region: Region) -> String {
        region.trackingUrl + path
    }
}
