import Foundation

/// All the types of tasks the `MessagingPush` module runs in the background queue
internal enum QueueTaskType: String {
    case registerPushToken
    case deletePushToken
    case trackPushMetric
}
