import Foundation

public protocol Queue {
    func addTask(type: QueueTaskType, data: Data) -> (success: Bool, queueStatus: QueueStatus)
}

// sourcery: InjectRegister = "Queue"
public class CioQueue: Queue {
    private let storage: QueueStorage
    private let siteId: SiteId

    init(siteId: SiteId, storage: QueueStorage) {
        self.storage = storage
        self.siteId = siteId
    }

    public func addTask(type: QueueTaskType, data: Data) -> (success: Bool, queueStatus: QueueStatus) {
        return storage.create(type: type, data: data)
    }
}
