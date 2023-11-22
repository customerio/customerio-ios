import CioInternalCommon

public struct MessagingInAppConfigOptions {
    public enum Factory {
        public static func create(siteId: String = "") -> MessagingInAppConfigOptions {
            MessagingInAppConfigOptions(
                siteId: siteId,
                region: Region.US
            )
        }
    }
    
    public enum Keys: String {
        case siteId
        case region
    }
    
    /// Immutable property to store the workspace site id set during SDK initialization.
    public private(set) var siteId: String
    /// Immutable property to store the workspace Region set during SDK initialization.
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
