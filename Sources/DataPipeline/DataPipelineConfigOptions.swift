import CioInternalCommon
import Foundation
import Segment

/// Configuration options for the Customer.io Data Pipeline module
public struct DataPipelineConfigOptions {
    /// Server key
    public let writeKey: String

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
}
