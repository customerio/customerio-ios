import Foundation

public struct QueueTaskItem: Codable, Equatable {
    let taskPersistedId: String
    let taskType: QueueTaskType
}
