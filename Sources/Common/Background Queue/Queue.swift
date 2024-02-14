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
    func deleteExpiredTasks()

    func getAllStoredTasks() -> [QueueTaskMetadata]

    func getTaskDetail(_ task: QueueTaskMetadata) -> TaskDetail?

    func deleteProcessedTask(_ task: QueueTaskMetadata)
}

public extension Queue {
    // Get list of all unprocessed tasks in background queue
    func getAllStoredTasks() -> [QueueTaskMetadata] {
        getAllStoredTasks()
    }

    // Delete already processed task from the background queue
    func deleteProcessedTask(_ task: QueueTaskMetadata) {
        deleteProcessedTask(task)
    }
}

public struct TaskDetail {
    public let data: Data
    public let taskType: QueueTaskType
    public let timestamp: Date
}

// sourcery: InjectRegister = "Queue"
public class CioQueue: Queue {
    private let storage: QueueStorage
    private let siteId: String
    private let jsonAdapter: JsonAdapter
    private let logger: Logger
    private let sdkConfig: SdkConfig
    private let queueTimer: SingleScheduleTimer
    private let dateUtil: DateUtil

    private var numberSecondsToScheduleTimer: Seconds {
        sdkConfig.backgroundQueueSecondsDelay
    }

    init(
        storage: QueueStorage,
        jsonAdapter: JsonAdapter,
        logger: Logger,
        sdkConfig: SdkConfig,
        queueTimer: SingleScheduleTimer,
        dateUtil: DateUtil
    ) {
        self.siteId = sdkConfig.siteId
        self.storage = storage
        self.jsonAdapter = jsonAdapter
        self.logger = logger
        self.sdkConfig = sdkConfig
        self.queueTimer = queueTimer
        self.dateUtil = dateUtil
    }

    public func getAllStoredTasks() -> [QueueTaskMetadata] {
        storage.getInventory()
    }

    public func getTaskDetail(_ task: QueueTaskMetadata) -> TaskDetail? {
        let persistedId = task.taskPersistedId
        let timestamp = task.createdAt
        guard let queueTaskType = QueueTaskType(rawValue: task.taskType) else { return nil }
        guard let task = storage.get(storageId: persistedId) else {
            logger.error("Fetching task with storage id: \(persistedId) failed.")
            return nil
        }
        return TaskDetail(data: task.data, taskType: queueTaskType, timestamp: timestamp)
    }

    public func deleteProcessedTask(_ task: QueueTaskMetadata) {
        let storageId = task.taskPersistedId
        if !storage.delete(storageId: storageId) {
            logger.error("Failed to delete task with storage id: \(storageId).")
        }
    }

    public func deleteExpiredTasks() {
        _ = storage.deleteExpired()
    }
}
