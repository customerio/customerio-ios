import Foundation

struct TrackEventQueueTaskData: Codable {
    let identifier: String
    /// JSON string: '{"foo": "bar"}'
    let attributesJsonString: String
}
