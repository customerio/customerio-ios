import CioInternalCommon

/**
 Configuration options for in-app messaging module

 Example usage:
 ```
 // create a new instance
 let inAppMessagingConfig = MessagingInAppConfigOptions.Factory.create(siteId: siteId, region: .US)
 ```
 */
// TODO: [CDP] Update docs to after module initialization changes for clarity on its usage
public struct MessagingInAppConfigOptions {
    // Used to create new instance of MessagingInAppConfigOptions when the MessagingInApp module is configured.
    // Each property of the MessagingInAppConfigOptions object can be modified by the user.
    public enum Factory {
        // TODO: [CDP] Rethink on how can we eliminate default value and force required properties
        public static func create(siteId: String = "", region: Region = Region.US) -> MessagingInAppConfigOptions {
            MessagingInAppConfigOptions(
                siteId: siteId,
                region: region
            )
        }
    }
    
    public enum Keys: String {
        case siteId
        case region
    }
    
    /// Property to store workspace Site ID set during module initialization
    /// Immutable for lazy updates only, can be updated using initialize method
    public private(set) var siteId: String
    /// Property to store workspace Region set during module initialization
    /// Immutable for lazy updates only, can be updated using initialize method
    public private(set) var region: Region

    public mutating func initialize(siteId: String, region: Region? = nil) {
        self.siteId = siteId
        if let region = region {
            self.region = region
        }
    }
    
    mutating func apply(with dictionary: [String: Any]) {
        // Each SDK config option should be able to be set from `dictionary`.
        // If one isn't provided, use current value instead.
        
        // If a parameter takes more logic to calculate, perform the logic up here.
        if let regionStringValue = dictionary[Keys.region.rawValue] as? String {
            self.region = Region.getRegion(from: regionStringValue)
        }

        // Construct object with all required parameters. Each config option should be updated from `dictionary` only if available.
        if let siteId = dictionary[Keys.siteId.rawValue] as? String {
            self.siteId = siteId
        }
    }
}
