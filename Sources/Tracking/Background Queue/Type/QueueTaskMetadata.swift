import Foundation

/// Pointer to full queue task in persistent storage.
/// This data structure is meant to be as small as possible with the
/// ability to hold all queue task metadata in memory at runtime.
public struct QueueTaskMetadata: Codable, Equatable, AutoLenses {
    let taskPersistedId: String
    let taskType: String
    /// Groups that this task belongs to where this task is the parent of the group.
    /// Tasks can be the parent of 0+ groups
    let groupsParent: QueueTaskGroups
    /// Groups that this task belongs to where this task a child of the group.
    /// Tasks can be the child of 0+ groups
    let groupsChild: QueueTaskGroups
}

internal extension QueueTaskMetadata {
    static var random: QueueTaskMetadata {
        QueueTaskMetadata(taskPersistedId: String.random,
                          taskType: QueueTaskType.trackEvent.rawValue,
                          groupsParent: nil,
                          groupsChild: nil)
    }
}
