import Foundation

struct Settings {
    var deviceToken: String
    var trackUrl: String
    var siteId: String
    var apiKey: String
    var bgQDelay: String
    var bgQMinTasks: String
    var isPushEnabled: Bool
    var isTrackScreenEnabled: Bool
    var isDeviceAttributeEnabled: Bool
    var isDebugModeEnabled: Bool
    
    init(deviceToken: String, trackUrl: String, siteId: String, apiKey: String, bgQDelay: String, bgQMinTasks: String, isPushEnabled: Bool, isTrackScreenEnabled: Bool, isDeviceAttributeEnabled: Bool, isDebugModeEnabled: Bool) {
        self.deviceToken = deviceToken
        self.trackUrl = trackUrl
        self.siteId = siteId
        self.apiKey = apiKey
        self.bgQDelay = bgQDelay
        self.bgQMinTasks = bgQMinTasks
        self.isPushEnabled = isPushEnabled
        self.isTrackScreenEnabled = isTrackScreenEnabled
        self.isDeviceAttributeEnabled = isDeviceAttributeEnabled
        self.isDebugModeEnabled = isDebugModeEnabled
    }
}
