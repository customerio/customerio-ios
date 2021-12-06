import Foundation

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
    /**
     Add a task to the queue to be performed sometime in the future.

     type - String data type to allow any module to add tasks to the queue. It's
            recommended to avoid hard-coded strings when adding tasks and instead use
            value from `QueueTaskType` String in each module.
     data - Probably a struct that contains "a snapshot" of the data needed to perform the
            background task (probably a network request).
     */
    func addTask<TaskData: Codable>(
        type: String,
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(data)"
        data: TaskData
    ) -> (success: Bool, queueStatus: QueueStatus)
    func run(onComplete: @escaping () -> Void)
}

// sourcery: InjectRegister = "Queue"
public class CioQueue: Queue {
    private let storage: QueueStorage
    private let siteId: SiteId
    private let runRequest: QueueRunRequest
    private let jsonAdapter: JsonAdapter
    private let logger: Logger
    private let sdkConfigStore: SdkConfigStore

    init(
        siteId: SiteId,
        storage: QueueStorage,
        runRequest: QueueRunRequest,
        jsonAdapter: JsonAdapter,
        logger: Logger,
        sdkConfigStore: SdkConfigStore
    ) {
        self.storage = storage
        self.siteId = siteId
        self.runRequest = runRequest
        self.jsonAdapter = jsonAdapter
        self.logger = logger
        self.sdkConfigStore = sdkConfigStore
    }

    public func addTask<T: Codable>(type: String, data: T) -> (success: Bool, queueStatus: QueueStatus) {
        logger.info("adding queue task \(type)")

        guard let data = jsonAdapter.toJson(data, encoder: nil) else {
            logger.error("fail adding queue task, json encoding fail.")

            return (success: false,
                    queueStatus: QueueStatus(queueId: siteId, numTasksInQueue: storage.getInventory().count))
        }

        logger.debug("added queue task data \(data.string ?? "")")

        let addTaskResult = storage.create(type: type, data: data)
        processQueueStatus(addTaskResult.queueStatus)

        return addTaskResult
    }

    public func run(onComplete: @escaping () -> Void) {
        logger.info("manually running background queue")

        runRequest.start(onComplete: onComplete)
    }

    private func processQueueStatus(_ status: QueueStatus) {
        logger.debug("processing queue status \(status).")
        let isManyTasksInQueue = status.numTasksInQueue >= sdkConfigStore.config.backgroundQueueMinNumberOfTasks

        let runQueue = isManyTasksInQueue

        if runQueue {
            logger.info("automatically running background queue")

            // not using [weak self] to assert that the queue will complete and callback once started.
            // this might keep this class in memory and not get garbage collected once customer is done using it
            // but it will get released once the queue is done running.
            runRequest.start {
                self.logger.info("automatic running background queue completed")
            }
        } else {
            logger.debug("queue skip running automatically")
        }
    }
}
