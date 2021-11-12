import Foundation

/**
 One source of truth get/set data for the background queue. Queue tasks inventory + tasks.

 The background queue data consists of:
 1. background queue tasks - data required to execute a background queue task
 2. The queue (aka: inventory) defining the ordered list of tasks to be executed.

 All data is persisted to the device file system.

 The queue tasks are stored as .json files (since json is easy to construct in swift)
 where each queue task is an individual file.

 The queue inventory is one .json file of a JSON array ordered from first to last task to run.

 Each queue inventory item, `QueueTaskMetadata`, points to a queue task, `QueueTask`.

 Yes, we could have the queue inventory (JSON array) contain all of the queue task data in it instead
 of having the queue inventory separated in the file system from the queue tasks themselves.
 We keep them separate to keep the inventory as small as possible so we don't need to worry about
 keeping the whole queue inventory in memory. Being a SDK, our memory footprint is important to stay
 as small as possible without concern. The inventory could get into hundreds or thousands of tasks
 if a customer app creates lots of tasks for an app that is in Airplane mode, for example.
 */
public protocol QueueStorage: AutoMockable {
    func getInventory() -> [QueueTaskMetadata]
    func saveInventory(_ inventory: [QueueTaskMetadata]) -> Bool

    func create(type: QueueTaskType, data: Data) -> (success: Bool, queueStatus: QueueStatus)
    func update(storageId: String, runResults: QueueTaskRunResults) -> Bool
    func get(storageId: String) -> QueueTask?
    func delete(storageId: String) -> Bool
}

// sourcery: InjectRegister = "QueueStorage"
public class FileManagerQueueStorage: QueueStorage {
    private let fileStorage: FileStorage
    private let jsonAdapter: JsonAdapter
    private let siteId: SiteId

    init(siteId: SiteId, fileStorage: FileStorage, jsonAdapter: JsonAdapter) {
        self.siteId = siteId
        self.fileStorage = fileStorage
        self.jsonAdapter = jsonAdapter
    }

    public func getInventory() -> [QueueTaskMetadata] {
        guard let data = fileStorage.get(type: .queueInventory, fileId: nil) else { return [] }

        let inventory: [QueueTaskMetadata] = jsonAdapter.fromJson(data, decoder: nil) ?? []

        return inventory
    }

    public func saveInventory(_ inventory: [QueueTaskMetadata]) -> Bool {
        guard let data = jsonAdapter.toJson(inventory, encoder: nil) else {
            return false
        }

        return fileStorage.save(type: .queueInventory, contents: data, fileId: nil)
    }

    public func create(type: QueueTaskType, data: Data) -> (success: Bool, queueStatus: QueueStatus) {
        var existingInventory = getInventory()
        let beforeCreateQueueStatus = QueueStatus(queueId: siteId, numTasksInQueue: existingInventory.count)

        let newTaskStorageId = UUID().uuidString
        let newQueueTask = QueueTask(storageId: newTaskStorageId, type: type, data: data,
                                     runResults: QueueTaskRunResults(totalRuns: 0))

        if !update(queueTask: newQueueTask) {
            return (success: false, queueStatus: beforeCreateQueueStatus)
        }

        let newQueueItem = QueueTaskMetadata(taskPersistedId: newTaskStorageId, taskType: type)
        existingInventory.append(newQueueItem)

        let updatedInventoryCount = existingInventory.count
        let afterCreateQueueStatus = QueueStatus(queueId: siteId, numTasksInQueue: updatedInventoryCount)

        if !saveInventory(existingInventory) {
            return (success: false, queueStatus: beforeCreateQueueStatus)
        }

        return (success: true, queueStatus: afterCreateQueueStatus)
    }

    public func update(storageId: String, runResults: QueueTaskRunResults) -> Bool {
        guard var existingQueueTask = get(storageId: storageId) else {
            return false
        }

        existingQueueTask = existingQueueTask.runResultsSet(runResults)

        return update(queueTask: existingQueueTask)
    }

    public func get(storageId: String) -> QueueTask? {
        guard let data = fileStorage.get(type: .queueTask, fileId: storageId),
              let task: QueueTask = jsonAdapter.fromJson(data, decoder: nil)
        else {
            return nil
        }

        return task
    }

    public func delete(storageId: String) -> Bool {
        // update inventory first so code that requests the inventory doesn't get the inventory item we are deleting
        var existingInventory = getInventory()
        existingInventory.removeAll { $0.taskPersistedId == storageId }
        let updateInventoryResult = saveInventory(existingInventory)

        if !updateInventoryResult { return false }

        // if this fails, we at least deleted the task from inventory so
        // it will not run again which is the most important thing
        return fileStorage.delete(type: .queueTask, fileId: storageId)
    }
}

public extension FileManagerQueueStorage {
    private func update(queueTask: QueueTask) -> Bool {
        guard let data = jsonAdapter.toJson(queueTask, encoder: nil) else {
            return false
        }

        return fileStorage.save(type: .queueTask, contents: data, fileId: queueTask.storageId)
    }
}
