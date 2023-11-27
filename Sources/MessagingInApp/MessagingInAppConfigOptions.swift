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
            return MessagingInAppConfigOptions(
                siteId: siteId,
                region: region
            )
        }

        public static func create(with dictionary: [String: Any]) -> MessagingInAppConfigOptions {
            // Each SDK config option should be able to be set from `dictionary`.
            // If one isn't provided, use current value instead.
            
            // Construct object with all required parameters. Each config option should be updated from `dictionary` only if available.
            let siteId = dictionary[Keys.siteId.rawValue] as? String
            let region = (dictionary[Keys.region.rawValue] as? String).map(Region.getRegion)

            // Use default config options as fallback
            let presetConfig = create()
            return MessagingInAppConfigOptions(
                siteId: siteId ?? presetConfig.siteId,
                region: region ?? presetConfig.region
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
}
