//
//  SdkConfigExtension.swift
//  Customer.io
//
//  Created by Holly Schilling on 2/11/26.
//

@_spi(Module) import CioInternalCommon
import CioAnalytics

extension SdkConfig {
    
    var autoScreenViewTrackingProperties: AutoScreenViewTrackingProperties? {
        extensionValue(
            for: DataPipelineConfigKey.autoTrackUIKitScreenViews.rawValue)
    }
    
    var apiHost: String {
        extensionValue(
            for: DataPipelineConfigKey.apiHost.rawValue,
            default: region.apiHost)
    }
    
    var cdnHost: String {
        extensionValue(
            for: DataPipelineConfigKey.cdnHost.rawValue,
            default: region.cdnHost)
    }
    
    var flushPolicies: [FlushPolicy] {
        extensionValue(
            for: DataPipelineConfigKey.flushPolicies.rawValue,
            default: [CountBasedFlushPolicy(), IntervalBasedFlushPolicy()])
    }
    
    var flushAt: Int {
        extensionValue(
            for: DataPipelineConfigKey.flushAt.rawValue,
            default: 20)
    }
    
    var flushInterval: Seconds {
        extensionValue(
            for: DataPipelineConfigKey.flushInterval.rawValue,
            default: 30)
    }
    
    var autoAddCustomerIODestination: Bool {
        extensionValue(
            for: DataPipelineConfigKey.autoAddCustomerIODestination.rawValue,
            default: true)
    }
    
    var trackApplicationLifecycleEvents: Bool {
        extensionValue(
            for: DataPipelineConfigKey.trackApplicationLifecycleEvents.rawValue,
            default: true)
    }
    var autoTrackDeviceAttributes: Bool {
        extensionValue(
            for: DataPipelineConfigKey.autoTrackDeviceAttributes.rawValue,
            default: true)
    }
    var migrationSiteId: String? {
        extensionValue(
            for: DataPipelineConfigKey.migrationSiteId.rawValue)
    }
    var screenViewUse: ScreenView {
        extensionValue(
            for: DataPipelineConfigKey.screenViewUse.rawValue,
            default: ScreenView.all)
    }
    
    var deepLinkCallback: DeepLinkCallback? {
        extensionValue(
            for: DataPipelineConfigKey.deepLinkCallback.rawValue)
        
    }
    
    func createDataPipelineConfigOptions() -> DataPipelineConfigOptions {
        // create plugins based on given configurations
        var configuredPlugins: [Plugin] = []
        if logLevel == CioLogLevel.debug {
            configuredPlugins.append(ConsoleLogger(diGraph: DIGraphShared.shared))
        }
        if let autoScreenViewTrackingProperties {
            configuredPlugins.append(AutoTrackingScreenViews(
                filterAutoScreenViewEvents: autoScreenViewTrackingProperties.filter,
                autoScreenViewBody: autoScreenViewTrackingProperties.additionalProperties
            ))
        }
        
        // create `DataPipelineConfigOptions` from given configurations
        let dataPipelineConfig = DataPipelineConfigOptions(
            cdpApiKey: cdpApiKey,
            apiHost: apiHost,
            cdnHost: cdnHost,
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
        
        if deepLinkCallback == nil {
            DIGraphShared.shared.logger.info("CIO: Switch to using explicit `deepLinkCallback` method as it's more reliable")
        }
        
        return dataPipelineConfig
    }
}
