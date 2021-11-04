import Foundation

/// Full task for the background queue
public struct QueueTask: Codable, AutoLenses, Equatable {
    /// ID used to store the task in persistant storage
    let storageId: String
    /// the type of task. used when running tasks
    let type: QueueTaskType
    /// data required to run the task
    let data: Data
    /// the current run results of the task. keeping track of the history of the task
    let runResults: QueueTaskRunResults
}
