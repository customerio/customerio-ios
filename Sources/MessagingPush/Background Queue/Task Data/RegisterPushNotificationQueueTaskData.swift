import Foundation

struct RegisterPushNotificationQueueTaskData: Codable {
    let profileIdentifier: String
    let deviceToken: String
    let lastUsed: Date
}
