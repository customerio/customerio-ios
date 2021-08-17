import Foundation

// disabling lint rule to allow 2 letter enum names: US, EU, etc.
// swiftlint:disable identifier_name
/**
 Region that your Customer.io Workspace is located in.

 The SDK will route traffic to the correct data center location depending on the `Region` that you use.
 */
public enum Region: String, Equatable {
    /// The United States (US) data center
    case US
    /// The European Union (EU) data center
    case EU

    internal var subdomainSuffix: String {
        switch self {
        case .US: return ""
        case .EU: return "-eu"
        }
    }

    internal var trackingUrl: String {
        "https://track\(subdomainSuffix).customer.io/api/v1"
    }
}

// swiftlint:enable identifier_name

internal struct SdkConfig: AutoLenses, Equatable {
    let siteId: String
    let apiKey: String
    let region: Region
}
