import Foundation

/// Full task for the background queue
public struct QueueTask: Codable, AutoLenses, Equatable {
    /// ID used to store the task in persistant storage
    public let storageId: String
    /// the type of task. used when running tasks
    public let type: String
    /// data required to run the task
    public let data: Data
    /// the current run results of the task. keeping track of the history of the task
    public let runResults: QueueTaskRunResults
}

internal extension QueueTask {
    static var random: QueueTask {
        QueueTask(storageId: String.random, type: QueueTaskType.identifyProfile.rawValue, data: Data(),
                  runResults: QueueTaskRunResults(totalRuns: 1))
    }
}
