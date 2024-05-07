import CioAnalytics
import CioInternalCommon
import Foundation

/// Defines configuration options for the Customer.io Data Pipeline module.
///
/// Use `SDKConfigBuilder` for constructing its instances. For detailed usage, see builder class documentation.
public struct DataPipelineConfigOptions {
    /// Server key
    public let cdpApiKey: String

    /// Host settings
    public let apiHost: String
    public let cdnHost: String

    /// Dispatching configurations
    public let flushAt: Int
    public let flushInterval: Seconds

    /// Segment configurations
    public let autoAddCustomerIODestination: Bool
    public let flushPolicies: [FlushPolicy]
    public let trackApplicationLifecycleEvents: Bool

    /// Configuration options for users to easily add available plugins
    public let autoTrackDeviceAttributes: Bool

    /// Configuration options required for migration from earlier versions
    public let migrationSiteId: String?

    /// Plugins identified based on configuration provided by the user
    let autoConfiguredPlugins: [Plugin]
}
