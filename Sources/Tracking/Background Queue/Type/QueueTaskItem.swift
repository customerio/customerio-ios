import Foundation

public struct QueueTaskItem: Codable, Equatable {
    let taskPersistedId: String
    let taskType: QueueTaskType
}

internal extension QueueTaskItem {
    static var random: QueueTaskItem {
        QueueTaskItem(taskPersistedId: String.random, taskType: .trackEvent)
    }
}
