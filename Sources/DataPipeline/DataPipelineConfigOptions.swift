import CioInternalCommon
import Foundation
import Segment

/**
 Configuration options for the Customer.io Data Pipeline module.

 Example use case:
 ```
 // create a new instance
 let dataPipelineConfig = DataPipelineConfigOptions.Factory.create(writeKey: "WRITE_KEY")
 // now, you can modify it
 dataPipelineConfig.apiHost = "https..."
 dataPipelineConfig.autoTrackScreenViews = false
 ```
 */
public struct DataPipelineConfigOptions {
    // Used to create new instance of DataPipelineConfigOptions when the DataPipeline module is configured.
    // Each property of the DataPipelineConfigOptions object can be modified by the user.
    public enum Factory {
        public static func create(writeKey: String) -> DataPipelineConfigOptions {
            DataPipelineConfigOptions(writeKey: writeKey)
        }

        public static func create(sdkConfig: SdkConfig) -> DataPipelineConfigOptions {
            let writeKey = "\(sdkConfig.siteId):\(sdkConfig.apiKey)"
            var result = DataPipelineConfigOptions(writeKey: writeKey)
            result.autoTrackDeviceAttributes = sdkConfig.autoTrackDeviceAttributes
            result.flushAt = sdkConfig.backgroundQueueMinNumberOfTasks
            result.flushInterval = sdkConfig.backgroundQueueSecondsDelay
            return result
        }
    }

    private static let defaultAPIHost = "cdp.customer.io/v1"
    private static let defaultCDNHost = "cdp.customer.io/v1"

    init(writeKey: String) {
        self.writeKey = writeKey
    }

    /// Site Id that will be used for tracking data migration
    public var siteId: String = ""

    /// Server key
    public let writeKey: String

    /// Host settings
    public var apiHost: String = Self.defaultAPIHost
    public var cdnHost: String = Self.defaultCDNHost

    /// Dispatching configurations
    public var flushAt: Int = 20
    public var flushInterval: Seconds = 30

    /// Segment configurations
    public var autoAddCustomerIODestination: Bool = true
    public var defaultSettings: Settings?
    public var flushPolicies: [FlushPolicy] = [CountBasedFlushPolicy(), IntervalBasedFlushPolicy()]
    public var flushQueue: DispatchQueue = .init(label: "com.segment.operatingModeQueue", qos: .utility)
    public var operatingMode: OperatingMode = .asynchronous
    public var trackApplicationLifecycleEvents: Bool = true

    /// Configuration options for users to easily add available plugins
    public var autoTrackDeviceAttributes: Bool = true
}
