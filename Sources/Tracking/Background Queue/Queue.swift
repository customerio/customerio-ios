import Foundation

public protocol Queue {
    func addTask(type: QueueTaskType, data: Data) -> (success: Bool, queueStatus: QueueStatus)
    func run(onComplete: @escaping () -> Void)
}

// sourcery: InjectRegister = "Queue"
public class CioQueue: Queue {
    private let storage: QueueStorage
    private let siteId: SiteId
    private let runRequest: QueueRunRequest

    init(siteId: SiteId, storage: QueueStorage, runRequest: QueueRunRequest) {
        self.storage = storage
        self.siteId = siteId
        self.runRequest = runRequest
    }

    public func addTask(type: QueueTaskType, data: Data) -> (success: Bool, queueStatus: QueueStatus) {
        let addTaskResult = storage.create(type: type, data: data)

        return (success: addTaskResult,
                queueStatus: QueueStatus(queueId: siteId, numTasksInQueue: storage.getInventory().count))
    }

    public func run(onComplete: @escaping () -> Void) {
        runRequest.start(onComplete: onComplete)
    }
}
