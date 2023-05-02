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
    /*
     Note: We are transitioning the code base to having a Queue function for every type of
     queue task. This is instead of having `Queue.addTask()` code scattered around the codebase.

     You may see some `addTaskX` functions below but not all until this refactor is completed.

     See list of refactors: https://github.com/customerio/issues/issues/6934
     */

    func addTrackInAppDeliveryTask(deliveryId: String, event: InAppMetric, metaData: [String: String])
    /**
     Asynchronously add a task to the queue to be performed sometime in the future.

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
        data: TaskData,
        groupStart: QueueTaskGroup?,
        blockingGroups: [QueueTaskGroup]?,
        onComplete: @escaping (ModifyQueueResult) -> Void
    )

    func run(onComplete: @escaping () -> Void)

    func deleteExpiredTasks()
}

public extension Queue {
    func addTrackInAppDeliveryTask(deliveryId: String, event: InAppMetric, metaData: [String: String] = [:]) {
        addTrackInAppDeliveryTask(deliveryId: deliveryId, event: event, metaData: metaData)
    }

    func addTask<TaskData: Codable>(
        type: String,
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(data)"
        data: TaskData,
        groupStart: QueueTaskGroup? = nil,
        blockingGroups: [QueueTaskGroup]? = nil,
        onComplete: ((ModifyQueueResult) -> Void)? = nil
    ) {
        addTask(type: type, data: data, groupStart: groupStart, blockingGroups: blockingGroups) { result in
            onComplete?(result)
        }
    }
}

// sourcery: InjectRegister = "Queue"
public class CioQueue: Queue {
    private let storage: QueueStorage
    private let siteId: SiteId
    private let runRequest: QueueRunRequest
    private let jsonAdapter: JsonAdapter
    private let logger: Logger
    private let sdkConfig: SdkConfig
    private let queueTimer: SingleScheduleTimer
    private let dateUtil: DateUtil
    private let threadUtil: ThreadUtil

    private var numberSecondsToScheduleTimer: Seconds {
        sdkConfig.backgroundQueueSecondsDelay
    }

    init(
        siteId: SiteId,
        storage: QueueStorage,
        runRequest: QueueRunRequest,
        jsonAdapter: JsonAdapter,
        logger: Logger,
        sdkConfig: SdkConfig,
        queueTimer: SingleScheduleTimer,
        dateUtil: DateUtil,
        threadUtil: ThreadUtil
    ) {
        self.storage = storage
        self.siteId = siteId
        self.runRequest = runRequest
        self.jsonAdapter = jsonAdapter
        self.logger = logger
        self.sdkConfig = sdkConfig
        self.queueTimer = queueTimer
        self.dateUtil = dateUtil
        self.threadUtil = threadUtil
    }

    public func addTrackInAppDeliveryTask(deliveryId: String, event: InAppMetric, metaData: [String: String]) -> ModifyQueueResult {
        addTask(
            type: QueueTaskType.trackDeliveryMetric.rawValue,
            data: TrackDeliveryEventRequestBody(
                type: .inApp,
                payload: DeliveryPayload(
                    deliveryId: deliveryId,
                    event: event,
                    timestamp: dateUtil.now,
                    metaData: metaData
                )
            )
        )
    }

    public func addTask<T: Codable>(
        type: String,
        data: T,
        groupStart: QueueTaskGroup?,
        blockingGroups: [QueueTaskGroup]?,
        onComplete: @escaping (ModifyQueueResult) -> Void
    ) {
        threadUtil.queueOnBackground { // because adding a task to the queue writes to the file system, schedule to run the operation on a background thread to not lock the UI thread.
            self.logger.info("adding task to the background queue \(type)")

            guard let data = self.jsonAdapter.toJson(data) else {
                self.logger.error("fail adding queue task, json encoding fail.")

                return onComplete((
                    success: false,
                    queueStatus: QueueStatus(queueId: self.siteId, numTasksInQueue: self.storage.getInventory().count)
                ))
            }

            self.logger.debug("added queue task data \(data.string ?? "")")

            let addTaskResult = self.storage.create(
                type: type,
                data: data,
                groupStart: groupStart,
                blockingGroups: blockingGroups
            )
            self.processQueueStatus(addTaskResult.queueStatus)

            onComplete((success: addTaskResult.success, queueStatus: addTaskResult.queueStatus))
        }
    }

    public func run(onComplete: @escaping () -> Void) {
        logger.info("queue run request sent")

        runRequest.start(onComplete: onComplete)
    }

    /// We determine the queue needs to run by (1) if there are many tasks in the queue
    /// (2) we schedule tasks to run sometime in the future.
    /// It is by grouping more then 1 task to run at a time in the queue that will save
    /// the device battery life so we try to do that when we can.
    private func processQueueStatus(_ status: QueueStatus) {
        logger.debug("processing queue status \(status).")
        let isManyTasksInQueue = status.numTasksInQueue >= sdkConfig.backgroundQueueMinNumberOfTasks

        if isManyTasksInQueue {
            logger.info("queue met criteria to run automatically")

            // cancel timer if one running since we will run the queue now
            queueTimer.cancel()

            // not using [weak self] to assert that the queue will complete and callback once started.
            // this might keep this class in memory and not get garbage collected once customer is done using it
            // but it will get released once the queue is done running.
            runRequest.start {
                self.logger.info("queue completed all tasks")
            }
        } else {
            // Not enough tasks in the queue yet to run it now, so let's schedule them to run in the future.
            // It's expected that only 1 timer instance exists and is running in the SDK.
            let didSchedule = queueTimer.scheduleIfNotAlready(seconds: numberSecondsToScheduleTimer) {
                self.logger.info("queue timer: now running queue")

                self.run {
                    self.logger.info("queue timer: queue done running")
                }
            }

            if didSchedule {
                logger.info("queue timer: scheduled to run queue in \(numberSecondsToScheduleTimer) seconds")
            }
        }
    }

    public func deleteExpiredTasks() {
        _ = storage.deleteExpired()
    }
}
