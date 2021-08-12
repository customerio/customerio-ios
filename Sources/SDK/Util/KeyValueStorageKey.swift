import Foundation

internal enum KeyValueStorageKey {
    static let keyPrefix = "CustomerIO-SDK-"

    case sharedInstanceSiteId
    case siteIdConfig(siteId: String)

    var string: String {
        switch self {
        case .sharedInstanceSiteId: return "\(Self.keyPrefix)shared-instance-site-id"
        case .siteIdConfig(let siteId): return "\(Self.keyPrefix)config-siteid-\(siteId)"
        }
    }
}
