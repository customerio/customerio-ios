import CioTracking
import Foundation

public struct CioSettings: Codable {
    public var trackUrl: String
    public var siteId: String
    public var apiKey: String
    public var bqSecondsDelay: TimeInterval
    public var bqMinNumberTasks: Int
    public var trackScreens: Bool
    public var trackDeviceAttributes: Bool

    public func configureCioSdk(config: inout CioSdkConfig) {
        config.trackingApiUrl = trackUrl
        config.backgroundQueueSecondsDelay = bqSecondsDelay
        config.backgroundQueueMinNumberOfTasks = bqMinNumberTasks
        config.autoTrackScreenViews = trackScreens
        config.autoTrackDeviceAttributes = trackDeviceAttributes
    }

    static func getFromCioSdk() -> CioSettings {
        let sdkConfig = CustomerIO.shared.config!

        return CioSettings(
            trackUrl: sdkConfig.trackingApiUrl,
            siteId: sdkConfig.siteId,
            apiKey: sdkConfig.apiKey,
            bqSecondsDelay: sdkConfig.backgroundQueueSecondsDelay,
            bqMinNumberTasks: sdkConfig.backgroundQueueMinNumberOfTasks,
            trackScreens: sdkConfig.autoTrackScreenViews,
            trackDeviceAttributes: sdkConfig.autoTrackDeviceAttributes
        )
    }
}
