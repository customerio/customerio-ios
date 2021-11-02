import Foundation

public protocol QueueStorage: AutoMockable {
    func getInventory() -> [QueueTaskItem]
    func saveInventory(_ inventory: [QueueTaskItem]) -> Bool

    func create(type: QueueTaskType, data: Data) -> Bool
    func update(storageId: String, runResults: QueueTaskRunResults) -> Bool
    func get(storageId: String) -> QueueTask?
    func delete(storageId: String) -> Bool
}

// sourcery: InjectRegister = "QueueStorage"
public class FileManagerQueueStorage: QueueStorage {
    private let fileStorage: FileStorage
    private let jsonAdapter: JsonAdapter

    init(fileStorage: FileStorage, jsonAdapter: JsonAdapter) {
        self.fileStorage = fileStorage
        self.jsonAdapter = jsonAdapter
    }

    public func getInventory() -> [QueueTaskItem] {
        guard let data = fileStorage.get(type: .queueInventory, fileId: nil) else { return [] }

        let inventory: [QueueTaskItem] = jsonAdapter.fromJson(data, decoder: nil) ?? []

        return inventory
    }

    public func saveInventory(_ inventory: [QueueTaskItem]) -> Bool {
        guard let data = jsonAdapter.toJson(inventory, encoder: nil) else {
            return false
        }

        return fileStorage.save(type: .queueInventory, contents: data, fileId: nil)
    }

    public func create(type: QueueTaskType, data: Data) -> Bool {
        let newTaskStorageId = UUID().uuidString
        let newQueueTask = QueueTask(storageId: newTaskStorageId, type: type, data: data,
                                     runResults: QueueTaskRunResults(totalRuns: 0))

        if !update(queueTask: newQueueTask) {
            return false
        }

        let newQueueItem = QueueTaskItem(taskPersistedId: newTaskStorageId, taskType: type)
        var existingInventory = getInventory()
        existingInventory.append(newQueueItem)
        return saveInventory(existingInventory)
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
