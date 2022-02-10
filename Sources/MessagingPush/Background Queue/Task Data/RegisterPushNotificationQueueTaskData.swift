import Foundation

struct RegisterPushNotificationQueueTaskData: Codable {
    let deviceToken: String
    let profileIdentifier : String
    let lastUsed: Date
    let attributes : DeviceAttributes
}

struct DeviceAttributes : Codable {
    let deviceOs : String
    let deviceModel : String
    let appVersion : String
    let cioSdkVersion : String
    let deviceLocale : String
    let pushSubscribed : String
}
