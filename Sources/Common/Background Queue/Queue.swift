import Foundation

public typealias ModifyQueueResult = (success: Bool, queueStatus: QueueStatus)

/**
 A background queue to perform actions in the background (probably network requests).
 A queue exists to make our public facing SDK functions synchronous:
 `CustomerIO.shared.trackEvent("foo")` where we perform the API call sometime in the future
 and handle errors/retry so customers don't have to.

 This is done by adding a task type + data that the task type needs to perform
 the network call later on.

 Best practices of using the queue:
 1. When you add tasks to the queue, provide all of the data the task needs
 to perform the task instead of, for example, reading data at the time of
 running the task. It's like you're taking a snapshot of the data at that current
 time when you add a task to the queue.
 2. Queue tasks (code executed in the queue runner) should be reserved for
 performing network code to "sync" the SDK data to the API. Other logic
 should not be performed in the queue task and should instead happen
 before the task runs.
 */
public protocol Queue: AutoMockable {
    func getAllStoredTasks(siteId: String) -> [QueueTaskMetadata]
    func getTaskDetail(_ task: QueueTaskMetadata, siteId: String) -> TaskDetail?
    func deleteProcessedTask(_ task: QueueTaskMetadata, siteId: String)
}

public struct TaskDetail {
    public let data: Data
    public let taskType: QueueTaskType
    public let timestamp: Date
}

// sourcery: InjectRegisterShared = "Queue"
public class CioQueue: Queue {
    private let storage: QueueStorage
    private let jsonAdapter: JsonAdapter
    private let logger: Logger
    private let queueTimer: SingleScheduleTimer
    private let dateUtil: DateUtil

    init(
        storage: QueueStorage,
        jsonAdapter: JsonAdapter,
        logger: Logger,
        queueTimer: SingleScheduleTimer,
        dateUtil: DateUtil
    ) {
        self.storage = storage
        self.jsonAdapter = jsonAdapter
        self.logger = logger
        self.queueTimer = queueTimer
        self.dateUtil = dateUtil
    }

    public func getAllStoredTasks(siteId: String) -> [QueueTaskMetadata] {
        storage.getInventory(siteId: siteId)
    }

    public func getTaskDetail(_ task: QueueTaskMetadata, siteId: String) -> TaskDetail? {
        let persistedId = task.taskPersistedId
        let timestamp = task.createdAt
        guard let queueTaskType = QueueTaskType(rawValue: task.taskType) else { return nil }
        guard let task = storage.get(storageId: persistedId, siteId: siteId) else {
            logger.error("Fetching task with storage id: \(persistedId) failed.")
            return nil
        }
        return TaskDetail(data: task.data, taskType: queueTaskType, timestamp: timestamp)
    }

    public func deleteProcessedTask(_ task: QueueTaskMetadata, siteId: String) {
        let storageId = task.taskPersistedId
        if !storage.delete(storageId: storageId, siteId: siteId) {
            logger.error("Failed to delete task with storage id: \(storageId).")
        }
    }
}
