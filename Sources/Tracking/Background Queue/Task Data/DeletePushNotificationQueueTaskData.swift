import Foundation

struct DeletePushNotificationQueueTaskData: Codable {
    let profileIdentifier: String
    let deviceToken: String
}
