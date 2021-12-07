import Foundation

/// Pointer to full queue task in persistent storage.
/// This data structure is meant to be as small as possible with the
/// ability to hold all queue task metadata in memory at runtime.
public struct QueueTaskMetadata: Codable, Equatable {
    let taskPersistedId: String
    let taskType: String
}

internal extension QueueTaskMetadata {
    static var random: QueueTaskMetadata {
        QueueTaskMetadata(taskPersistedId: String.random, taskType: QueueTaskType.trackEvent.rawValue)
    }
}
