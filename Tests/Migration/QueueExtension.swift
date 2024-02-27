@testable import CioInternalCommon
import Foundation

public enum QueueTaskGroup {
    case identifiedProfile(identifier: String)
    case registeredPushToken(token: String)

    public var string: String {
        switch self {
        case .identifiedProfile(let identifier): return "identified_profile_\(identifier)"
        case .registeredPushToken(let token): return "registered_push_token\(token)"
        }
    }
}

public extension FileManagerQueueStorage {
    func create(
        siteId: String,
        type: String,
        data: Data,
        groupStart: QueueTaskGroup?,
        blockingGroups: [QueueTaskGroup]?
    ) -> CreateQueueStorageTaskResult {
        lock.lock()
        defer { lock.unlock() }

        var existingInventory = getInventory(siteId: siteId)
        let beforeCreateQueueStatus = QueueStatus(queueId: siteId, numTasksInQueue: existingInventory.count)

        let newTaskStorageId = UUID().uuidString
        let newQueueTask = QueueTask(
            storageId: newTaskStorageId,
            type: type,
            data: data,
            runResults: QueueTaskRunResults(totalRuns: 0)
        )

        if !update(queueTask: newQueueTask, siteId: siteId) {
            return CreateQueueStorageTaskResult(success: false, queueStatus: beforeCreateQueueStatus, createdTask: nil)
        }

        let newQueueItem = QueueTaskMetadata(
            taskPersistedId: newTaskStorageId,
            taskType: type,
            groupStart: groupStart?.string,
            groupMember: blockingGroups?.map(\.string),
            createdAt: dateUtil.now
        )
        existingInventory.append(newQueueItem)

        let updatedInventoryCount = existingInventory.count
        let afterCreateQueueStatus = QueueStatus(queueId: siteId, numTasksInQueue: updatedInventoryCount)

        if !saveInventory(existingInventory, siteId: siteId) {
            return CreateQueueStorageTaskResult(success: false, queueStatus: beforeCreateQueueStatus, createdTask: nil)
        }

        // It's more accurate for us to get the inventory item from the inventory instead of just returning
        // newQueueItem. This is because queue storage when saving to storage might modify the metadata object
        // such as removing milliseconds from Date. By getting the inventory item directly from device storage,
        // we return the most accurate data on the inventory item.
        guard let createdTask = getInventory(siteId: siteId).first(where: { $0.taskPersistedId == newQueueItem.taskPersistedId })
        else {
            logger.error("expected to find task \(newQueueItem) to be in the inventory but it wasn't")
            return CreateQueueStorageTaskResult(success: false, queueStatus: beforeCreateQueueStatus, createdTask: nil)
        }

        return CreateQueueStorageTaskResult(
            success: true,
            queueStatus: afterCreateQueueStatus,
            createdTask: createdTask
        )
    }
}
