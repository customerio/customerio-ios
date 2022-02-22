import Foundation

struct RegisterPushNotificationQueueTaskData: Codable {
    let deviceToken: String
    let profileIdentifier : String
    let lastUsed: Date
    let attributes : [String: String]?
}
