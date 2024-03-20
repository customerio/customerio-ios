import CioDataPipelines
import CioInternalCommon
import Foundation

// Stores all of the SDK settings that can be changed by the mobile app.
// Note: This struct may not contain *all* of the settings that can be changed in the CIO SDK.
public struct CioSettings: Codable {
    public var siteId: String
    public var cdpApiKey: String
    public var apiHost: String
    public var cdnHost: String
    public var flushInterval: Double
    public var flushAt: Int
    public var trackScreens: Bool
    public var debugSdkMode: Bool
    public var trackDeviceAttributes: Bool

    public static func getFromCioSdk() -> CioSettings {
        let sdkConfig = DataPipeline.moduleConfig
        let logLevel = DIGraphShared.shared.logger.logLevel
        return CioSettings(
            siteId: sdkConfig?.migrationSiteId ?? "",
            cdpApiKey: sdkConfig?.cdpApiKey ?? "",
            apiHost: sdkConfig?.apiHost ?? "",
            cdnHost: sdkConfig?.cdnHost ?? "",
            flushInterval: sdkConfig?.flushInterval ?? 30,
            flushAt: sdkConfig?.flushAt ?? 10,
            trackScreens: false, // Track screen is no longer SDK configurable property. If you want to enable/disable autoScreenTrack then refer AppDelegate for use case. Setting default value as false for sample app
            debugSdkMode: logLevel == .debug,
            trackDeviceAttributes: sdkConfig?.autoTrackDeviceAttributes ?? true
        )
    }
}
