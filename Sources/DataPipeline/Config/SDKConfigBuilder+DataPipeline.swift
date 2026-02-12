import CioAnalytics
import Foundation

@_spi(Module)
import CioInternalCommon

#if canImport(UIKit)
import UIKit
#endif



struct AutoScreenViewTrackingProperties {
    var additionalProperties: (() -> [String: Any])? = nil
    var filter: ((UIViewController) -> Bool)? = nil
}


public extension SDKConfigBuilder {
    
    @discardableResult
    func flushPolicies(_ policies: [FlushPolicy]) -> SDKConfigBuilder {
        setExtensionValue(policies, forKey: DataPipelineConfigKey.flushPolicies.rawValue)
    }
    
    @discardableResult
    func flushAt(_ flushAt: Int) -> SDKConfigBuilder {
        setExtensionValue(flushAt, forKey: DataPipelineConfigKey.flushAt.rawValue)
    }
    
    @discardableResult
    func flushInterval(_ flushInterval: Seconds) -> SDKConfigBuilder {
        setExtensionValue(flushInterval, forKey: DataPipelineConfigKey.flushInterval.rawValue)
    }
    
    @discardableResult
    func autoAddCustomerIODestination(_ autoAdd: Bool) -> SDKConfigBuilder {
        setExtensionValue(autoAdd, forKey: DataPipelineConfigKey.autoAddCustomerIODestination.rawValue)
    }
    
    @discardableResult
    func trackApplicationLifecycleEvents(_ track: Bool) -> SDKConfigBuilder {
        setExtensionValue(track, forKey: DataPipelineConfigKey.trackApplicationLifecycleEvents.rawValue)
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
    func autoTrackUIKitScreenViews(
        enabled: Bool = true,
        autoScreenViewBody: (() -> [String: Any])? = nil,
        filterAutoScreenViewEvents: ((UIViewController) -> Bool)? = nil
    ) -> SDKConfigBuilder {
        if enabled {
            let properties = AutoScreenViewTrackingProperties(
                additionalProperties: autoScreenViewBody,
                filter: filterAutoScreenViewEvents
            )
            return setExtensionValue(
                properties,
                forKey: DataPipelineConfigKey.autoTrackUIKitScreenViews.rawValue
            )
        } else {
            return setExtensionValue(false, forKey: DataPipelineConfigKey.autoTrackUIKitScreenViews.rawValue)
        }
    }
#endif
    
    
    /// Enable this property if you want SDK to automatic track device attributes such as
    /// operating system, device locale, device model, app version etc.
    @discardableResult
    func autoTrackDeviceAttributes(_ autoTrack: Bool) -> SDKConfigBuilder {
        setExtensionValue(autoTrack, forKey: DataPipelineConfigKey.autoTrackDeviceAttributes.rawValue)
    }
    
    @discardableResult
    func migrationSiteId(_ siteId: String) -> SDKConfigBuilder {
        setExtensionValue(siteId, forKey: DataPipelineConfigKey.migrationSiteId.rawValue)
    }
    
    @discardableResult
    func screenViewUse(screenView: ScreenView) -> SDKConfigBuilder {
        setExtensionValue(screenView, forKey: DataPipelineConfigKey.screenViewUse.rawValue)
    }
    
    @discardableResult
    @available(iOSApplicationExtension, unavailable)
    func deepLinkCallback(_ callback: @escaping DeepLinkCallback) -> SDKConfigBuilder {
        setExtensionValue(callback, forKey: DataPipelineConfigKey.deepLinkCallback.rawValue)
    }
    
    @discardableResult
    func apiHost(_ apiHost: String) -> SDKConfigBuilder {
        setExtensionValue(apiHost, forKey: DataPipelineConfigKey.apiHost.rawValue)
    }
    
    @discardableResult
    func cdnHost(_ cdnHost: String) -> SDKConfigBuilder {
        setExtensionValue(cdnHost, forKey: DataPipelineConfigKey.cdnHost.rawValue)
    }
}


