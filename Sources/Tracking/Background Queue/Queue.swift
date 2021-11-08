import Foundation

/**
 A background queue to perform actions in the background (probably network requests).
 A queue exists to make our public facing SDK functions synchronous:
 `CustomerIO.shared.trackEvent("foo")` where we perform the API call sometime in the future
 and handle errors/retry so customers don't have to.

 The queue is designed with the main purpose of performing API calls. Let's show an example of
 how it's recommended you use the queue and how *not* to use the queue.

 Let's say you're identifying a profile.
 ```
 // recommended use of the background queue
 func identifyProfile(identifier: String, data: Encodable) {
    // perform all operations here, first before touching the queue
    keyValueStorage.save(identifier)

    if deviceTokenSavedToDifferentProfile {
       // it's OK to add tasks to the queue here before we identify the new profile
       queue.addTask(.deleteDeviceToken, identifier: oldProfileIdentifier)
       keyValueStorage.delete(deviceToken)
    }

    // then, add a background queue task
    queue.addTask(.identifyProfile, identifier: identifier)
 }

 // then later on in the code, the background queue task runs
 // *all* of our logic for identifying a new profile.
 func runQueueTask() {
     httpClient.identifyProfile(newProfileIdentifier
 }
 ```

 Not recommended way of using the background queue:
 ```
 func identifyProfile(identifier: String, data: Encodable) {
    queue.addTask(.identifyProfile, identifier: identifier, oldProfileIdentifier)
 }

 // then later on in the code, the background queue task runs
 // *all* of our logic for identifying a new profile.
 func runQueueTask() {
     let newProfileIdentifier = ...

     keyValueStorage.save(identifier)

     if deviceTokenSavedToDifferentProfile {
        httpClient.delete(deviceTokenFromOldProfile)

        keyValueStorage.delete(deviceToken)
     }

     httpClient.identifyProfile(newProfileIdentifier
 }
 ```
 */
public protocol Queue: AutoMockable {
    /**
     Add a task to the queue to be performed sometime in the future.

     `data` - Probably a struct that contains "a snapshot" of the data needed to perform the
     background task (probably a network request).
     */
    func addTask<TaskData: Codable>(
        type: QueueTaskType,
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

    public func addTask<T: Codable>(type: QueueTaskType, data: T) -> (success: Bool, queueStatus: QueueStatus) {
        guard let data = jsonAdapter.toJson(data, encoder: nil) else {
            return (success: false,
                    queueStatus: QueueStatus(queueId: siteId, numTasksInQueue: storage.getInventory().count))
        }

        let addTaskResult = storage.create(type: type, data: data)

        let queueStatus = QueueStatus(queueId: siteId, numTasksInQueue: storage.getInventory().count)
        processQueueStatus(queueStatus)

        return (success: addTaskResult, queueStatus: queueStatus)
    }

    public func run(onComplete: @escaping () -> Void) {
        logger.verbose("Manually running background queue")

        runRequest.start(onComplete: onComplete)
    }

    private func processQueueStatus(_ status: QueueStatus) {
        logger.verbose("Processing queue status \(status).")
        let isManyTasksInQueue = status.numTasksInQueue >= sdkConfigStore.config.backgroundQueueMinNumberOfTasks

        let runQueue = isManyTasksInQueue

        if runQueue {
            logger.verbose("Automatically running background queue")

            runRequest.start { [weak self] in
                self?.logger.verbose("Automatic running background queue completed")
            }
        }
    }
}
