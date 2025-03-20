import CioDataPipelines
import Foundation

struct Settings: Codable {
    var dataPipelines: DataPipelinesSettings
    var messaging: MessagingPushAPNSettings
    var inApp: MessagingInAppSettings
    var internalSettings: InternalSettings
}

struct DataPipelinesSettings: Codable {
    var cdpApiKey: String
    var siteId: String
    var region: Region
    var autoTrackDeviceAttributes: Bool
    var autoTrackUIKitScreenViews: Bool
    var trackApplicationLifecycleEvents: Bool
    var screenViewUse: ScreenViewUse
    var logLevel: LogLevel
}

enum Region: String, Codable {
    case US
    case EU
}

extension Region {
    func toCIORegion() -> CioDataPipelines.Region {
        switch self {
        case .US:
            return .US
        case .EU:
            return .EU
        }
    }
}

enum ScreenViewUse: String, Codable {
    case All
    case InApp
}

extension ScreenViewUse {
    func toCIOScreenViewUse() -> CioDataPipelines.ScreenView {
        switch self {
        case .All:
            return .all
        case .InApp:
            return .inApp
        }
    }
}

enum LogLevel: String, Codable {
    case Debug
    case Info
    case Error
}

extension LogLevel {
    func toCIOLogLevel() -> CioDataPipelines.CioLogLevel {
        switch self {
        case .Debug:
            return .debug
        case .Info:
            return .info
        case .Error:
            return .error
        }
    }
}

struct MessagingPushAPNSettings: Codable {
    var autoFetchDeviceToken: Bool
    var autoTrackPushEvents: Bool
    var showPushAppInForeground: Bool
}

struct MessagingInAppSettings: Codable {
    var siteId: String
    var region: Region
}

struct InternalSettings: Codable {
    var cdnHost: String
    var apiHost: String
    var inAppEnvironment: InAppEnvironment
    var testMode: Bool
}

enum InAppEnvironment: Equatable, Codable {
    case Development
    case Production
    case Custom(url: String)
}
