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
    func getInventory(siteId: String) -> [QueueTaskMetadata]
    func get(storageId: String, siteId: String) -> QueueTask?
    func delete(storageId: String, siteId: String) -> Bool
}

// sourcery: InjectRegisterShared = "QueueStorage"
public class FileManagerQueueStorage: QueueStorage {
    private let fileStorage: FileStorage
    private let jsonAdapter: JsonAdapter
    let logger: Logger
    let dateUtil: DateUtil
    private var inventoryStore: QueueInventoryMemoryStore

    let lock: Lock

    init(
        fileStorage: FileStorage,
        jsonAdapter: JsonAdapter,
        lockManager: LockManager,
        logger: Logger,
        dateUtil: DateUtil,
        inventoryStore: QueueInventoryMemoryStore
    ) {
        self.fileStorage = fileStorage
        self.jsonAdapter = jsonAdapter
        self.logger = logger
        self.dateUtil = dateUtil
        self.lock = lockManager.getLock(id: .queueStorage)
        self.inventoryStore = inventoryStore
    }

    public func getInventory(siteId: String) -> [QueueTaskMetadata] {
        lock.lock()
        defer { lock.unlock() }

        if let inventoryCache = inventoryStore.inventory {
            return inventoryCache
        }

        guard let data = fileStorage.get(siteId: siteId, type: .queueInventory, fileId: nil) else { return [] }
        guard let readInventory: [QueueTaskMetadata] = jsonAdapter.fromJson(data) else { return [] }
        inventoryStore.inventory = readInventory // set in-memory cache for next time getter is called

        return readInventory
    }

    public func saveInventory(_ newInventory: [QueueTaskMetadata], siteId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let data = jsonAdapter.toJson(newInventory) else { return false }

        let successfullySavedInStorage = fileStorage.save(siteId: siteId, type: .queueInventory, contents: data, fileId: nil)
        guard successfullySavedInStorage else {
            return false
        }

        // the inventory is the BQ's single source of truth for what tasks are in the BQ. It's important that the inventory cache reflects what's in SDK storage so only update
        // it after we successfully save the storage.
        // If there is a failed save to file system, the item added to the BQ will get ignored to try and keep the SDK into an error-free state.
        inventoryStore.inventory = newInventory // update cache

        return true
    }

    public func get(storageId: String, siteId: String) -> QueueTask? {
        lock.lock()
        defer { lock.unlock() }

        guard let data = fileStorage.get(siteId: siteId, type: .queueTask, fileId: storageId),
              let task: QueueTask = jsonAdapter.fromJson(data)
        else {
            return nil
        }

        return task
    }

    public func delete(storageId: String, siteId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        // update inventory first so code that requests the inventory doesn't get the inventory item we are deleting
        var existingInventory = getInventory(siteId: siteId)
        existingInventory.removeAll { $0.taskPersistedId == storageId }
        let updateInventoryResult = saveInventory(existingInventory, siteId: siteId)

        if !updateInventoryResult { return false }

        // if this fails, we at least deleted the task from inventory so
        // it will not run again which is the most important thing
        return fileStorage.delete(siteId: siteId, type: .queueTask, fileId: storageId)
    }
}

public extension FileManagerQueueStorage {
    func update(queueTask: QueueTask, siteId: String) -> Bool {
        guard let data = jsonAdapter.toJson(queueTask) else {
            return false
        }

        return fileStorage.save(siteId: siteId, type: .queueTask, contents: data, fileId: queueTask.storageId)
    }
}

public struct CreateQueueStorageTaskResult {
    public let success: Bool
    public let queueStatus: QueueStatus
    public let createdTask: QueueTaskMetadata?
}
