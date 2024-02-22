import CioInternalCommon
import Foundation
import Segment

/// Builder class designed to facilitate the creation of `SdkConfig` and `DataPipelineConfigOptions`.
/// The builder pattern allows for a fluent and intuitive way to set up configuration options for
/// the SDK, ensuring all required and optional settings are appropriately configured before the
/// SDK is initialized.
///
/// Usage Example:
/// ```
/// let config = SDKConfigBuilder(writeKey: "your_write_key")
///   .apiHost("your_api_host")
///   .flushAt(30)
///   // additional configuration as needed...
///   .build()
/// // Use `config` for initializing the SDK...
/// ```
public struct SDKConfigBuilder {
    // default static values for configuration options
    private static let defaultAPIHost = "cdp.customer.io/v1"
    private static let defaultCDNHost = "cdp.customer.io/v1"

    // configuration options for SdkConfig
    private var logLevel: CioLogLevel = .error

    // configuration options for DataPipelineConfigOptions
    private let writeKey: String
    private var apiHost: String = SDKConfigBuilder.defaultAPIHost
    private var cdnHost: String = SDKConfigBuilder.defaultCDNHost
    private var flushAt: Int = 20
    private var flushInterval: Seconds = 30
    private var autoAddCustomerIODestination: Bool = true
    private var defaultSettings: Settings?
    private var flushPolicies: [FlushPolicy] = [CountBasedFlushPolicy(), IntervalBasedFlushPolicy()]
    private var flushQueue: DispatchQueue = .init(label: "com.segment.operatingModeQueue", qos: .utility)
    private var operatingMode: OperatingMode = .asynchronous
    private var trackApplicationLifecycleEvents: Bool = true
    private var autoTrackDeviceAttributes: Bool = true

    // allow construction of builder with required configurations only
    public init(writeKey: String) {
        self.writeKey = writeKey
    }

    @discardableResult
    public mutating func logLevel(_ logLevel: CioLogLevel) -> SDKConfigBuilder {
        self.logLevel = logLevel
        return self
    }

    @discardableResult
    public mutating func apiHost(_ apiHost: String) -> SDKConfigBuilder {
        self.apiHost = apiHost
        return self
    }

    @discardableResult
    public mutating func cdnHost(_ cdnHost: String) -> SDKConfigBuilder {
        self.cdnHost = cdnHost
        return self
    }

    @discardableResult
    public mutating func flushAt(_ flushAt: Int) -> SDKConfigBuilder {
        self.flushAt = flushAt
        return self
    }

    @discardableResult
    public mutating func flushInterval(_ flushInterval: Seconds) -> SDKConfigBuilder {
        self.flushInterval = flushInterval
        return self
    }

    @discardableResult
    public mutating func autoAddCustomerIODestination(_ autoAdd: Bool) -> SDKConfigBuilder {
        autoAddCustomerIODestination = autoAdd
        return self
    }

    @discardableResult
    public mutating func defaultSettings(_ settings: Settings?) -> SDKConfigBuilder {
        defaultSettings = settings
        return self
    }

    @discardableResult
    public mutating func flushPolicies(_ policies: [FlushPolicy]) -> SDKConfigBuilder {
        flushPolicies = policies
        return self
    }

    @discardableResult
    public mutating func flushQueue(_ queue: DispatchQueue) -> SDKConfigBuilder {
        flushQueue = queue
        return self
    }

    @discardableResult
    public mutating func operatingMode(_ mode: OperatingMode) -> SDKConfigBuilder {
        operatingMode = mode
        return self
    }

    @discardableResult
    public mutating func trackApplicationLifecycleEvents(_ track: Bool) -> SDKConfigBuilder {
        trackApplicationLifecycleEvents = track
        return self
    }

    @discardableResult
    public mutating func autoTrackDeviceAttributes(_ autoTrack: Bool) -> SDKConfigBuilder {
        autoTrackDeviceAttributes = autoTrack
        return self
    }

    public func build() -> SDKConfigBuilderResult {
        // create `SdkConfig`` from given configurations
        var sdkConfig = SdkConfig.Factory.create(siteId: "", apiKey: "", region: .US)
        sdkConfig.logLevel = logLevel

        // create `DataPipelineConfigOptions` from given configurations
        let dataPipelineConfig = DataPipelineConfigOptions(
            writeKey: writeKey,
            apiHost: apiHost,
            cdnHost: cdnHost,
            flushAt: flushAt,
            flushInterval: flushInterval,
            autoAddCustomerIODestination: autoAddCustomerIODestination,
            defaultSettings: defaultSettings,
            flushPolicies: flushPolicies,
            flushQueue: flushQueue,
            operatingMode: operatingMode,
            trackApplicationLifecycleEvents: trackApplicationLifecycleEvents,
            autoTrackDeviceAttributes: autoTrackDeviceAttributes
        )

        return (sdkConfig: sdkConfig, dataPipelineConfig: dataPipelineConfig)
    }
}

/// Tuple type for the result of the `SDKConfigBuilder`'s `build` method.
/// Contains both `SdkConfig` and `DataPipelineConfigOptions` instances.
public typealias SDKConfigBuilderResult = (sdkConfig: SdkConfig, dataPipelineConfig: DataPipelineConfigOptions)
