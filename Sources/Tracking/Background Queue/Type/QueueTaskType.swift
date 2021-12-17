import Foundation

/// All the types of tasks the `Tracking` module runs in the background queue
internal enum QueueTaskType: String {
    case identifyProfile
    case trackEvent
}
