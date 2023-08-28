import Foundation

/// All the types of tasks the `Tracking` module runs in the background queue
enum QueueTaskType: String {
    case identifyProfile
    case trackEvent
    case registerPushToken
    case deletePushToken
    case trackPushMetric
}
