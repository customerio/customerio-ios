import Foundation

struct IdentifyProfileQueueTaskData: Codable {
    let identifier: String
    /// JSON string: '{"foo": "bar"}'
    let attributesJsonString: String?

    enum CodingKeys: String, CodingKey {
        case identifier
        case attributesJsonString = "attributes_json_string"
    }
}
