import Foundation

struct DeletePushNotificationQueueTaskData: Codable {
    let profileIdentifier: String
    let deviceToken: String

    enum CodingKeys: String, CodingKey {
        case profileIdentifier = "profile_identifier"
        case deviceToken = "device_token"
    }
}
