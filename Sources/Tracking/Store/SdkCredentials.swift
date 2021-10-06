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

    internal var productionTrackingUrl: String {
        switch self {
        case .US: return "https://track.customer.io/api/v1"
        case .EU: return "https://track-eu.customer.io/api/v1"
        }
    }
}

// swiftlint:enable identifier_name

public struct SdkCredentials: AutoLenses, Equatable {
    public let apiKey: String
    public let region: Region
}
