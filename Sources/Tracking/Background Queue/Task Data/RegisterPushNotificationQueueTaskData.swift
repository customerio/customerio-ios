import Foundation

struct RegisterPushNotificationQueueTaskData: Codable {
    let profileIdentifier: String
    let attributesJsonString: String?

    enum CodingKeys: String, CodingKey {
        case profileIdentifier = "profile_identifier"
        case attributesJsonString = "attributes_json_string"
    }
}
