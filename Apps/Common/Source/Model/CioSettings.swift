import CioTracking
import Foundation

// Stores all of the SDK settings that can be changed by the mobile app.
// Note: This struct may not contain *all* of the settings that can be changed in the CIO SDK.
public struct CioSettings: Codable {
    public var trackUrl: String
    public var siteId: String
    public var cdpApiKey: String
    public var apiHost: String
    public var cdnHost: String
    public var flushInterval: Double
    public var flushAt: Int
    public var trackScreens: Bool
    public var debugSdkMode: Bool
    public var trackDeviceAttributes: Bool

    public func configureCioSdk(config: inout CioSdkConfig) {
//        config.trackingApiUrl = trackUrl
//        config.backgroundQueueSecondsDelay = bqSecondsDelay
//        config.backgroundQueueMinNumberOfTasks = bqMinNumberTasks
//        config.autoTrackScreenViews = trackScreens
//        config.autoTrackDeviceAttributes = trackDeviceAttributes
//
//        if debugSdkMode {
//            config.logLevel = .debug
//        }
    }

    public static func getFromCioSdk() -> CioSettings {
        let sdkConfig = CustomerIO.shared.config!

        return CioSettings(
            trackUrl: sdkConfig.trackingApiUrl,
            siteId: sdkConfig.siteId,
            cdpApiKey: sdkConfig.cdpApiKey,
            apiHost: sdkConfig.apiHost,
            cdnHost: sdkConfig.cdnHost,
            flushInterval: sdkConfig.backgroundQueueSecondsDelay,
            flushAt: sdkConfig.backgroundQueueMinNumberOfTasks,
            trackScreens: sdkConfig.autoTrackScreenViews,
            debugSdkMode: sdkConfig.logLevel == CioLogLevel.debug,
            trackDeviceAttributes: sdkConfig.autoTrackDeviceAttributes
        )
    }
}
