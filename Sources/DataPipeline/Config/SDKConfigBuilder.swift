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
public class CioSdkConfigGenericBuilder<ResultType: SDKConfigBuilderResult> {
    // helper configuration options to ease setting up other configurations such as `apiHost` and `cdnHost`
    var region: Region = .US
    var autoTrackUIKitScreenViews: Bool = false
    var autoScreenViewBody: (() -> [String: Any])?
    #if canImport(UIKit)
    var filterAutoScreenViewEvents: ((UIViewController) -> Bool)?
    #endif

    // configuration options for SdkConfig
    var logLevel: CioLogLevel = .error

    // configuration options for DataPipelineConfigOptions
    let cdpApiKey: String
    var apiHost: String?
    var cdnHost: String?
    var flushAt: Int = 20
    var flushInterval: Seconds = 30
    var autoAddCustomerIODestination: Bool = true
    var flushPolicies: [FlushPolicy] = [CountBasedFlushPolicy(), IntervalBasedFlushPolicy()]
    var trackApplicationLifecycleEvents: Bool = true
    var autoTrackDeviceAttributes: Bool = true
    var migrationSiteId: String?
    var screenViewUse: ScreenView = .all

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
    public func region(_ region: Region) -> Self {
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
    ) -> Self {
        autoTrackUIKitScreenViews = enabled
        self.autoScreenViewBody = autoScreenViewBody
        self.filterAutoScreenViewEvents = filterAutoScreenViewEvents
        return self
    }
    #endif

    /// To help you get setup with the SDK or debug SDK, change the log level of logs you wish to
    /// view from the SDK.
    @discardableResult
    public func logLevel(_ logLevel: CioLogLevel) -> Self {
        self.logLevel = logLevel
        return self
    }

    @discardableResult
    public func apiHost(_ apiHost: String) -> Self {
        self.apiHost = apiHost
        return self
    }

    @discardableResult
    public func cdnHost(_ cdnHost: String) -> Self {
        self.cdnHost = cdnHost
        return self
    }

    @discardableResult
    public func flushAt(_ flushAt: Int) -> Self {
        self.flushAt = flushAt
        return self
    }

    @discardableResult
    public func flushInterval(_ flushInterval: Seconds) -> Self {
        self.flushInterval = flushInterval
        return self
    }

    @discardableResult
    func autoAddCustomerIODestination(_ autoAdd: Bool) -> Self {
        autoAddCustomerIODestination = autoAdd
        return self
    }

    @discardableResult
    public func flushPolicies(_ policies: [FlushPolicy]) -> Self {
        flushPolicies = policies
        return self
    }

    @discardableResult
    public func trackApplicationLifecycleEvents(_ track: Bool) -> Self {
        trackApplicationLifecycleEvents = track
        return self
    }

    /// Enable this property if you want SDK to automatic track device attributes such as
    /// operating system, device locale, device model, app version etc.
    @discardableResult
    public func autoTrackDeviceAttributes(_ autoTrack: Bool) -> Self {
        autoTrackDeviceAttributes = autoTrack
        return self
    }

    @discardableResult
    public func migrationSiteId(_ siteId: String) -> Self {
        migrationSiteId = siteId
        return self
    }

    @discardableResult
    public func screenViewUse(screenView: ScreenView) -> Self {
        screenViewUse = screenView
        return self
    }

    @available(iOSApplicationExtension, unavailable)
    open func build() -> ResultType {
        assertionFailure(
            "This method should not be called directly. Use `SDKConfigAndCallbackBuilder.build()` instead."
        )
        // swiftlint:disable:next force_cast - OK for method that should NOT be used.
        return NSObject() as! ResultType
    }

    @available(iOSApplicationExtension, unavailable)
    func createSDKAndPipelineConfig() -> (SdkConfig, DataPipelineConfigOptions) {
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
            screenViewUse: screenViewUse,
            autoConfiguredPlugins: configuredPlugins
        )

        return (sdkConfig, dataPipelineConfig)
    }
}

@available(*, deprecated, message: "Use CioSdkConfigBuilder instead")
public class SDKConfigBuilder: CioSdkConfigGenericBuilder<SDKConfigBuilder.SDKConfigBuilderResultImpl> {
    @available(iOSApplicationExtension, unavailable)
    override open func build() -> SDKConfigBuilderResultImpl {
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
            screenViewUse: screenViewUse,
            autoConfiguredPlugins: configuredPlugins
        )

        return SDKConfigBuilderResultImpl(
            sdkConfig: sdkConfig,
            dataPipelineConfig: dataPipelineConfig
        )
    }

    public struct SDKConfigBuilderResultImpl: SDKConfigBuilderResult {
        public var sdkConfig: SdkConfig
        public var dataPipelineConfig: DataPipelineConfigOptions
    }
}

public class CioSdkConfigBuilder: CioSdkConfigGenericBuilder<CioSdkConfigBuilder.SDKConfigAndCallbackBuilderResultImpl> {
    // configure deep-linking for whole SDK
    private var deepLinkCallback: DeepLinkCallback?

    @discardableResult
    @available(iOSApplicationExtension, unavailable)
    public func deepLinkCallback(_ callback: @escaping DeepLinkCallback) -> Self {
        deepLinkCallback = callback
        return self
    }

    @available(iOSApplicationExtension, unavailable)
    override open func build() -> SDKConfigAndCallbackBuilderResultImpl {
        let (sdkConfig, dataPipelineConfig) = super.createSDKAndPipelineConfig()

        return SDKConfigAndCallbackBuilderResultImpl(
            sdkConfig: sdkConfig,
            dataPipelineConfig: dataPipelineConfig,
            deepLinkCallback: deepLinkCallback
        )
    }

    public struct SDKConfigAndCallbackBuilderResultImpl: CioSdkConfigBuilderResult {
        public let sdkConfig: SdkConfig
        public let dataPipelineConfig: DataPipelineConfigOptions
        public let deepLinkCallback: DeepLinkCallback?
    }
}

/// Type for the result of the `SDKConfigBuilder`'s `build` method.
/// Contains both `SdkConfig` and `DataPipelineConfigOptions` instances.
public protocol SDKConfigBuilderResult {
    var sdkConfig: SdkConfig { get }
    var dataPipelineConfig: DataPipelineConfigOptions { get }
}

/// Type for the result of the `CioSdkConfigBuilder`'s `build` method.
/// Contains both `SdkConfig`, `DataPipelineConfigOptions` and `DeepLinkCallback` instances.
public protocol CioSdkConfigBuilderResult: SDKConfigBuilderResult {
    var deepLinkCallback: DeepLinkCallback? { get }
}
