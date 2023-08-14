@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class QueueStorageTest: UnitTest {
    var storage: FileManagerQueueStorage!

    let fileStorageMock = FileStorageMock()

    override func setUp() {
        super.setUp()

        storage = FileManagerQueueStorage(
            fileStorage: fileStorageMock,
            jsonAdapter: jsonAdapter,
            lockManager: lockManager,
            sdkConfig: sdkConfig,
            logger: log,
            dateUtil: dateUtilStub,
            inventoryStore: diGraph.queueInventoryMemoryStore
        )
    }

    // MARK: saveInventory

    func test_saveInventory_givenSaveSuccessful_expectReturnTrue_expectCacheUpdated() {
        let givenInventory = [QueueTaskMetadata.random]
        fileStorageMock.saveReturnValue = true

        let actual = storage.saveInventory(givenInventory)

        XCTAssertTrue(actual)
        XCTAssertEqual(diGraph.queueInventoryMemoryStore.inventory, givenInventory)
    }

    func test_saveInventory_givenSaveUnsuccessful_expectReturnFalse_expectCacheNotUpdated() {
        fileStorageMock.saveReturnValue = false

        let actual = storage.saveInventory([QueueTaskMetadata.random])

        XCTAssertFalse(actual)
        XCTAssertNil(diGraph.queueInventoryMemoryStore.inventory)
    }

    // MARK: getInventory

    func test_getInventory_expectReadFromFileSystemOnce_expectUseCache() {
        fileStorageMock.getReturnValue = "[]".data!

        _ = storage.getInventory()
        XCTAssertEqual(fileStorageMock.getCallsCount, 1)

        _ = storage.getInventory()
        XCTAssertEqual(fileStorageMock.getCallsCount, 1)
    }

    func test_getInventory_givenNoInventoryInFileSystem_expectEmptyInventory_expectCacheNotUpdated() {
        fileStorageMock.getReturnValue = nil

        let actual = storage.getInventory()

        XCTAssertEqual(actual, [])
        XCTAssertNil(diGraph.queueInventoryMemoryStore.inventory)
    }

    // MARK: create

    func test_create_givenFileStorageDoesNotSaveTask_expectDoNotUpdateInventory_expectFalse() {
        fileStorageMock.saveReturnValue = false

        let givenData = "hello ami!".data!
        let givenType = String.random

        let actual = storage.create(
            type: givenType,
            data: givenData,
            groupStart: .identifiedProfile(identifier: String.random),
            blockingGroups: [.identifiedProfile(identifier: String.random)]
        )

        XCTAssertEqual(fileStorageMock.saveCallsCount, 1) // only create task call, not trying to update inventory
        XCTAssertFalse(actual.success)
        XCTAssertEqual(actual.queueStatus, QueueStatus(
            queueId: testSiteId,
            numTasksInQueue: 0
        )) // Number of tasks should be 0 since creating a task failed.
    }

    func test_create_givenFileStorageDoesNotUpdateInventory_expectFalse() {
        // We want the saveInventory task to fail.
        // To do that, the first call to fileStorage.save is successful (we are saving the task) but the second call is
        // failed (we are saving the inventory).
        var returnValues = [true, false]
        fileStorageMock.saveClosure = { _, _, _ in
            returnValues.removeFirst()
        }

        let givenData = "hello ami!".data!
        let givenType = String.random

        let actual = storage.create(
            type: givenType,
            data: givenData,
            groupStart: .identifiedProfile(identifier: String.random),
            blockingGroups: [.identifiedProfile(identifier: String.random)]
        )

        XCTAssertEqual(
            fileStorageMock.saveCallsCount,
            2
        ) // 2 save *attempts* were made: try to save task, try to save inventory
        // Since saving the inventory failed, we expect `storage.create()` to have failed entirely like the request to
        // `storage.create()` was ignored.
        XCTAssertFalse(actual.success)
        XCTAssertEqual(actual.queueStatus, QueueStatus(
            queueId: testSiteId,
            numTasksInQueue: 0
        )) // Number of tasks should be 0 since creating a task failed.
    }
}

// MARK: integration tests

#if !os(Linux) // LINUX_DISABLE_FILEMANAGER
class QueueStorageIntegrationTest: UnitTest {
    var storage: FileManagerQueueStorage!

    override func setUp() {
        super.setUp()

        storage = getStorageInstance()
    }

    // MARK: getInventory

    func test_getInventory_givenNeverSavedInventoryBefore_expectEmpty() {
        let actual = storage.getInventory()

        XCTAssertEqual(actual, [])
    }

    func test_getInventory_givenSavedPreviousInventory_expectGetExistingInventory() {
        let expected = [QueueTaskMetadata.random]
        _ = storage.saveInventory(expected)

        let actual = storage.getInventory()

        XCTAssertEqual(actual, expected)
    }

    func test_getInventory_givenMultipleStorageInstances_expectCacheToBeSharedAcrossInstances() {
        _ = storage.saveInventory([QueueTaskMetadata.random]) // some some non-empty inventory for instances first read of the cache.

        let storage2 = getStorageInstance()

        // Assert the cache has been loaded at least once on both instances for accuracy of test
        _ = storage.getInventory()
        _ = storage2.getInventory()

        // Save new inventory on 1 instance
        let expected = [QueueTaskMetadata.random]
        _ = storage.saveInventory(expected)

        // All instances should have the same inventory now.
        XCTAssertEqual(storage.getInventory(), expected)
        XCTAssertEqual(storage2.getInventory(), expected)
    }

    // The queue inventory has an in-memory store. Test that the inventory is also persisted so when in-memory store recreated, inventory is still valid.
    func test_getInventory_givenRecreateSdk_expectInventoryIsPersisted() {
        let expected = [QueueTaskMetadata.random]
        _ = storage.saveInventory(expected)

        XCTAssertTrue(diGraph.queueInventoryMemoryStore.inventory != nil)
        setUp() // recreate storage instance and it's dependencies
        XCTAssertTrue(diGraph.queueInventoryMemoryStore.inventory == nil)

        let actual = storage.getInventory()

        XCTAssertEqual(actual, expected)
    }

    // MARK: create

    func test_create_expectSaveNewTaskToStorage_expectUpdateInventory_expectTrue() {
        let givenData = "hello ami!".data!
        let givenType = String.random

        let actual = storage.create(
            type: givenType,
            data: givenData,
            groupStart: .identifiedProfile(identifier: String.random),
            blockingGroups: [.identifiedProfile(identifier: String.random)]
        )

        XCTAssertTrue(actual.success)
        XCTAssertEqual(actual.queueStatus, QueueStatus(queueId: testSiteId, numTasksInQueue: 1))

        let expectedInventory = [actual.createdTask]
        let actualInventory = storage.getInventory()

        XCTAssertEqual(expectedInventory, actualInventory)
    }

    // MARK: update

    func test_update_givenNoTaskSaved_expectFalse() {
        let actual = storage.update(storageId: String.random, runResults: QueueTaskRunResults(totalRuns: 1))

        XCTAssertFalse(actual)
    }

    func test_update_expectUpdateTaskToStorage_expectInventoryNotUpdated_expectTrue() {
        let givenType = String.random
        let givenData = String.random.data!
        let givenCreatedTask = storage.create(type: givenType, data: givenData, groupStart: nil, blockingGroups: nil)
            .createdTask!
        let expectedInventory = storage.getInventory() // we do not expect inventory to be updated after updating task

        let runResultsBeforeUpdate = storage.get(storageId: givenCreatedTask.taskPersistedId)!.runResults
        let expectedUpdateTaskValue = QueueTaskRunResults(totalRuns: runResultsBeforeUpdate.totalRuns + 1)
        XCTAssertNotEqual(runResultsBeforeUpdate, expectedUpdateTaskValue)

        let actualUpdatedTaskSuccess = storage.update(
            storageId: givenCreatedTask.taskPersistedId,
            runResults: expectedUpdateTaskValue
        )

        let runResultsAfterUpdate = storage.get(storageId: givenCreatedTask.taskPersistedId)!.runResults

        XCTAssertTrue(actualUpdatedTaskSuccess)
        XCTAssertEqual(storage.getInventory(), expectedInventory)
        XCTAssertEqual(expectedUpdateTaskValue, runResultsAfterUpdate)
    }

    // MARK: get

    func test_get_givenNoTaskInStorage_expectNil() {
        _ = storage.create(type: .random, data: "".data, groupStart: nil, blockingGroups: nil)

        XCTAssertNil(storage.get(storageId: String.random))
    }

    func test_get_givenTaskInStorage_expectGetSavedTask() {
        let givenType = String.random
        let givenData = String.random.data!
        let createdTaskInventoryItem = storage.create(
            type: givenType,
            data: givenData,
            groupStart: nil,
            blockingGroups: nil
        ).createdTask!
        let expected = QueueTask(
            storageId: createdTaskInventoryItem.taskPersistedId,
            type: givenType,
            data: givenData,
            runResults: QueueTaskRunResults(totalRuns: 0)
        )

        let actual = storage.get(storageId: createdTaskInventoryItem.taskPersistedId)

        XCTAssertNotNil(actual)
        XCTAssertEqual(actual, expected)
    }

    // MARK: delete

    func test_delete_expectDeleteTaskPreviouslyAdded() {
        _ = storage.create(
            type: String.random,
            data: Data(),
            groupStart: .identifiedProfile(identifier: String.random),
            blockingGroups: [.identifiedProfile(identifier: String.random)]
        )

        var inventory = storage.getInventory()
        XCTAssertEqual(inventory.count, 1)
        let givenStorageId = inventory[0].taskPersistedId
        XCTAssertNotNil(storage.get(storageId: givenStorageId))

        let actual = storage.delete(storageId: givenStorageId)

        XCTAssertTrue(actual)
        inventory = storage.getInventory()
        XCTAssertEqual(inventory.count, 0)
        XCTAssertNil(storage.get(storageId: givenStorageId))
    }

    // MARK: deleteExpired

    func test_deleteExpired_givenNoTasksInQueue_expectDeleteNoTasks() {
        let tasksDeleted = storage.deleteExpired()

        XCTAssertEqual(tasksDeleted.count, 0)
    }

    func test_deleteExpired_givenTasksNotExpired_expectDeleteNoTasks() {
        dateUtilStub.givenNow = Date() // make newly created tasks not expired
        _ = storage.create(type: String.random, data: "".data, groupStart: nil, blockingGroups: nil)

        let tasksDeleted = storage.deleteExpired()

        XCTAssertEqual(tasksDeleted.count, 0)
    }

    func test_deleteExpired_givenTasksStartOfGroupAndExpired_expectDeleteNoTasks() {
        dateUtilStub.givenNow = Date().subtract(10, .day) // make newly created tasks expired
        _ = storage.create(
            type: String.random,
            data: "".data,
            groupStart: QueueTaskGroup.identifiedProfile(identifier: String.random),
            blockingGroups: nil
        )

        let tasksDeleted = storage.deleteExpired()

        XCTAssertEqual(tasksDeleted.count, 0)
    }

    func test_deleteExpired_givenTasksNoStartOfGroupAndExpired_expectDeleteTasksExpired() {
        let givenGroupOfTasks = QueueTaskGroup.identifiedProfile(identifier: String.random)
        dateUtilStub.givenNow = Date().subtract(10, .day) // make newly created tasks expired
        _ = storage.create(
            type: String.random,
            data: "".data,
            groupStart: givenGroupOfTasks,
            blockingGroups: nil
        )
        let expectedNotDeleted = storage.getInventory()[0]
        _ = storage.create(
            type: String.random,
            data: "".data,
            groupStart: nil,
            blockingGroups: [givenGroupOfTasks]
        )
        let expectedDeleted = storage.getInventory()[1]
        XCTAssertNotEqual(expectedNotDeleted.taskPersistedId, expectedDeleted.taskPersistedId)

        let tasksDeleted = storage.deleteExpired()

        XCTAssertEqual(tasksDeleted.count, 1)
        XCTAssertEqual(tasksDeleted[0], expectedDeleted)

        let actualInventory = storage.getInventory()
        XCTAssertEqual(actualInventory.count, 1)
        XCTAssertEqual(actualInventory[0], expectedNotDeleted)
    }
}

extension QueueStorageIntegrationTest {
    private func getStorageInstance() -> FileManagerQueueStorage {
        FileManagerQueueStorage(
            fileStorage: diGraph.fileStorage,
            jsonAdapter: jsonAdapter,
            lockManager: lockManager,
            sdkConfig: sdkConfig,
            logger: log,
            dateUtil: dateUtilStub,
            inventoryStore: diGraph.queueInventoryMemoryStore
        )
    }
}
#endif
