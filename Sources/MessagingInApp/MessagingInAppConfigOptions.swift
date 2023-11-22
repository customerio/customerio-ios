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
}
