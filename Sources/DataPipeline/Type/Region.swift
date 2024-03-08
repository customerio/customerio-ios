import CioInternalCommon

// These URLs are for requesting CDP settings from the CDP API, and must align with server's CDP regional configuration.
extension Region {
    var apiHost: String {
        switch self {
        case .US: return "cdp.customer.io/v1"
        case .EU: return "cdp-eu.customer.io/v1"
        }
    }

    var cdnHost: String {
        switch self {
        case .US: return "cdp.customer.io/v1"
        case .EU: return "cdp-eu.customer.io/v1"
        }
    }
}
