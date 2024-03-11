import CioInternalCommon
import Foundation
import Segment

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
    public let defaultSettings: Settings?
    public let flushPolicies: [FlushPolicy]
    public let flushQueue: DispatchQueue
    public let operatingMode: OperatingMode
    public let trackApplicationLifecycleEvents: Bool

    /// Configuration options for users to easily add available plugins
    public let autoTrackDeviceAttributes: Bool

    /// Configuration options required for migration from earlier versions
    public let migrationSiteId: String?
}
