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
}

public extension Region {
    static func getRegion(from regionStr: String) -> Region {
        switch regionStr.uppercased() {
        case "US":
            return Region.US
        case "EU":
            return Region.EU
        default:
            return Region.US
        }
    }
}

// swiftlint:enable identifier_name
