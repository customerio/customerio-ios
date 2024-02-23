import CioInternalCommon

/// Defines configuration options for the Customer.io In-App Messaging module.
///
/// Use `MessagingInAppConfigBuilder` for constructing its instances. For detailed usage, see builder class documentation.
public struct MessagingInAppConfigOptions {
    public let siteId: String
    public let region: Region
}
