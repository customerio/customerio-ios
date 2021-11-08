import Foundation

struct IdentifyProfileQueueTaskData: Codable {
    let identifier: String
    /// JSON string: '{"foo": "bar"}'
    let attributesJsonString: String?
}
