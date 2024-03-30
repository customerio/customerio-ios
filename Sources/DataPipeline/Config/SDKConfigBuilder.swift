import CioAnalytics
import CioInternalCommon
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Builder class designed to facilitate the creation of `SdkConfig` and `DataPipelineConfigOptions`.
/// The builder pattern allows for a fluent and intuitive way to set up configuration options for
/// the SDK, ensuring all required and optional settings are appropriately configured before the
/// SDK is initialized.
///
/// **Usage Example:**
///
/// ```
/// let config = SDKConfigBuilder(cdpApiKey: "your_cdp_api_key")
///   .logLevel(.debug)
///   .flushAt(30)
///   // additional configuration as needed...
///   .build()
/// // Use `config` for initializing the SDK...
/// ```
public class SDKConfigBuilder {
    // helper configuration options to ease setting up other configurations such as `apiHost` and `cdnHost`
    private var region: Region = .US
    private var autoTrackUIKitScreenViews: Bool = false
    private var autoScreenViewBody: (() -> [String: Any])?
    #if canImport(UIKit)
    private var filterAutoScreenViewEvents: ((UIViewController) -> Bool)?
    #endif

    // configuration options for SdkConfig
    private var logLevel: CioLogLevel = .error

    // configuration options for DataPipelineConfigOptions
    private let cdpApiKey: String
    private var apiHost: String?
    private var cdnHost: String?
    private var flushAt: Int = 20
    private var flushInterval: Seconds = 30
    private var autoAddCustomerIODestination: Bool = true
    private var flushPolicies: [FlushPolicy] = [CountBasedFlushPolicy(), IntervalBasedFlushPolicy()]
    private var trackApplicationLifecycleEvents: Bool = true
    private var autoTrackDeviceAttributes: Bool = true
    private var migrationSiteId: String?

    /// Initializes new `SDKConfigBuilder` with required configuration options.
    /// - Parameters:
    ///   - cdpApiKey: Customer.io Data Pipeline API Key
    public init(cdpApiKey: String) {
        self.cdpApiKey = cdpApiKey
    }

    /// Specifies the workspace region to ensure CDP requests are routed to the correct regional endpoint.
    /// Default values for apiHost and cdnHost are determined by the region.
    /// However, if apiHost or cdnHost are manually specified, those values override region-based defaults.
    @discardableResult
    public func region(_ region: Region) -> SDKConfigBuilder {
        self.region = region
        return self
    }

    #if canImport(UIKit)
    /// Enable this property if you want SDK to automatically track screen views for UIKit based apps.
    /// - Parameters:
    ///   - enabled: `true` to enable auto tracking of screen views, `false` to disable.
    ///   - autoScreenViewBody: Closure that returns a dictionary of properties to be sent with the
    ///     screen view event. This closure is called every time a screen view event is sent and can be used
    ///     to override our defaults and provide custom values in the body of the `screen` event..
    ///   - filterAutoScreenViewEvents: Closure that returns a boolean value indicating whether
    ///     the screen view event should be sent. Return `true` from function if you would like the screen
    ///     view event to be tracked. This closure is called every time a screen view event is about to be
    ///     tracked. Default value is `nil`, which uses the default filter function packaged by the SDK.
    ///     Provide a non-nil value to not call the SDK's filtering.
    @discardableResult
    public func autoTrackUIKitScreenViews(
        enabled: Bool = true,
        autoScreenViewBody: (() -> [String: Any])? = nil,
        filterAutoScreenViewEvents: ((UIViewController) -> Bool)? = nil
    ) -> SDKConfigBuilder {
        autoTrackUIKitScreenViews = enabled
        self.autoScreenViewBody = autoScreenViewBody
        self.filterAutoScreenViewEvents = filterAutoScreenViewEvents
        return self
    }
    #endif

    /// To help you get setup with the SDK or debug SDK, change the log level of logs you wish to
    /// view from the SDK.
    @discardableResult
    public func logLevel(_ logLevel: CioLogLevel) -> SDKConfigBuilder {
        self.logLevel = logLevel
        return self
    }

    @discardableResult
    public func apiHost(_ apiHost: String) -> SDKConfigBuilder {
        self.apiHost = apiHost
        return self
    }

    @discardableResult
    public func cdnHost(_ cdnHost: String) -> SDKConfigBuilder {
        self.cdnHost = cdnHost
        return self
    }

    @discardableResult
    public func flushAt(_ flushAt: Int) -> SDKConfigBuilder {
        self.flushAt = flushAt
        return self
    }

    @discardableResult
    public func flushInterval(_ flushInterval: Seconds) -> SDKConfigBuilder {
        self.flushInterval = flushInterval
        return self
    }

    @discardableResult
    func autoAddCustomerIODestination(_ autoAdd: Bool) -> SDKConfigBuilder {
        autoAddCustomerIODestination = autoAdd
        return self
    }

    @discardableResult
    public func flushPolicies(_ policies: [FlushPolicy]) -> SDKConfigBuilder {
        flushPolicies = policies
        return self
    }

    @discardableResult
    public func trackApplicationLifecycleEvents(_ track: Bool) -> SDKConfigBuilder {
        trackApplicationLifecycleEvents = track
        return self
    }

    /// Enable this property if you want SDK to automatic track device attributes such as
    /// operating system, device locale, device model, app version etc.
    @discardableResult
    public func autoTrackDeviceAttributes(_ autoTrack: Bool) -> SDKConfigBuilder {
        autoTrackDeviceAttributes = autoTrack
        return self
    }

    @discardableResult
    public func migrationSiteId(_ siteId: String) -> SDKConfigBuilder {
        migrationSiteId = siteId
        return self
    }

    @available(iOSApplicationExtension, unavailable)
    public func build() -> SDKConfigBuilderResult {
        // create `SdkConfig` from given configurations
        let sdkConfig = SdkConfig.Factory.create(
            logLevel: logLevel
        )

        // create plugins based on given configurations
        var configuredPlugins: [Plugin] = []
        if logLevel == CioLogLevel.debug {
            configuredPlugins.append(ConsoleLogger(diGraph: DIGraphShared.shared))
        }
        if autoTrackUIKitScreenViews {
            configuredPlugins.append(AutoTrackingScreenViews(
                filterAutoScreenViewEvents: filterAutoScreenViewEvents,
                autoScreenViewBody: autoScreenViewBody
            ))
        }

        // create `DataPipelineConfigOptions` from given configurations
        let dataPipelineConfig = DataPipelineConfigOptions(
            cdpApiKey: cdpApiKey,
            apiHost: apiHost ?? region.apiHost,
            cdnHost: cdnHost ?? region.cdnHost,
            flushAt: flushAt,
            flushInterval: flushInterval,
            autoAddCustomerIODestination: autoAddCustomerIODestination,
            flushPolicies: flushPolicies,
            trackApplicationLifecycleEvents: trackApplicationLifecycleEvents,
            autoTrackDeviceAttributes: autoTrackDeviceAttributes,
            migrationSiteId: migrationSiteId,
            autoConfiguredPlugins: configuredPlugins
        )

        return (sdkConfig: sdkConfig, dataPipelineConfig: dataPipelineConfig)
    }
}

/// Tuple type for the result of the `SDKConfigBuilder`'s `build` method.
/// Contains both `SdkConfig` and `DataPipelineConfigOptions` instances.
public typealias SDKConfigBuilderResult = (sdkConfig: SdkConfig, dataPipelineConfig: DataPipelineConfigOptions)
