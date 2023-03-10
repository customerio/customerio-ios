@testable import Common
import Foundation
import SharedTests
import XCTest

class QueueStorageTest: UnitTest {
    var storage: FileManagerQueueStorage!

    let fileStorageMock = FileStorageMock()

    override func setUp() {
        super.setUp()

        storage = FileManagerQueueStorage(
            siteId: testSiteId,
            fileStorage: fileStorageMock,
            jsonAdapter: jsonAdapter,
            lockManager: lockManager,
            sdkConfig: sdkConfig,
            logger: log,
            dateUtil: dateUtilStub
        )
    }

    // MARK: saveInventory

    func test_saveInventory_givenSaveSuccessful_expectTrue() {
        fileStorageMock.saveReturnValue = true

        let actual = storage.saveInventory([QueueTaskMetadata.random])

        XCTAssertTrue(actual)
    }

    func test_saveInventory_givenSaveUnsuccessful_expectFalse() {
        fileStorageMock.saveReturnValue = false

        let actual = storage.saveInventory([QueueTaskMetadata.random])

        XCTAssertFalse(actual)
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

        storage = FileManagerQueueStorage(
            siteId: testSiteId,
            fileStorage: diGraph.fileStorage,
            jsonAdapter: jsonAdapter,
            lockManager: lockManager,
            sdkConfig: sdkConfig,
            logger: log,
            dateUtil: dateUtilStub
        )
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

    // MARK: deleteGroup

    func test_deleteTasksMemberOfGroup_givenTasksMemberOfGroupToDelete_expectAllTasksInGroupToDelete() {
        let givenStartOfTheGroup = QueueTaskGroup.identifiedProfile(identifier: String.random)

        _ = storage.create(
            type: String.random,
            data: Data(),
            groupStart: givenStartOfTheGroup,
            blockingGroups: nil
        )

        _ = storage.create(
            type: String.random,
            data: Data(),
            groupStart: nil,
            blockingGroups: [givenStartOfTheGroup]
        )

        _ = storage.create(
            type: String.random,
            data: Data(),
            groupStart: nil,
            blockingGroups: [givenStartOfTheGroup]
        )

        let inventory = storage.getInventory()
        let expectedTasksNotDeleted = [inventory[0]]
        let expectedTasksDeleted = [inventory[1], inventory[2]]

        XCTAssertEqual(expectedTasksDeleted, storage.deleteTasksMemberOfGroup(groupId: givenStartOfTheGroup.string))
        XCTAssertEqual(expectedTasksNotDeleted, storage.getInventory())
    }

    func test_deleteTasksMemberOfGroup_expectTasksNotInGroupNotDeleted() {
        let givenStartOfTheGroup = QueueTaskGroup.identifiedProfile(identifier: String.random)
        let givenStartOfAnotherGroup = QueueTaskGroup.registeredPushToken(token: String.random)

        _ = storage.create(
            type: String.random,
            data: Data(),
            groupStart: givenStartOfTheGroup,
            blockingGroups: nil
        )

        _ = storage.create(
            type: String.random,
            data: Data(),
            groupStart: nil,
            blockingGroups: [givenStartOfTheGroup]
        )

        _ = storage.create(
            type: String.random,
            data: Data(),
            groupStart: nil,
            blockingGroups: nil
        )

        _ = storage.create(
            type: String.random,
            data: Data(),
            groupStart: nil,
            blockingGroups: [givenStartOfAnotherGroup]
        )

        let inventory = storage.getInventory()
        let expectedTasksNotDeleted = [inventory[0], inventory[2], inventory[3]]
        let expectedTasksDeleted = [inventory[1]]

        XCTAssertEqual(expectedTasksDeleted, storage.deleteTasksMemberOfGroup(groupId: givenStartOfTheGroup.string))
        XCTAssertEqual(expectedTasksNotDeleted, storage.getInventory())
    }

    func test_deleteTasksMemberOfGroup_givenDeletedTasksStartNewGroup_expectMultipleGroupsBeDeleted() {
        let givenStartOfTheGroup = QueueTaskGroup.identifiedProfile(identifier: String.random)
        let givenStartOfAnotherGroup = QueueTaskGroup.registeredPushToken(token: String.random)

        _ = storage.create(
            type: String.random,
            data: Data(),
            groupStart: givenStartOfTheGroup,
            blockingGroups: nil
        )

        _ = storage.create(
            type: String.random,
            data: Data(),
            groupStart: nil,
            blockingGroups: [givenStartOfTheGroup]
        )

        _ = storage.create(
            type: String.random,
            data: Data(),
            groupStart: givenStartOfAnotherGroup,
            blockingGroups: [givenStartOfTheGroup]
        )

        _ = storage.create(
            type: String.random,
            data: Data(),
            groupStart: nil,
            blockingGroups: [givenStartOfAnotherGroup]
        )

        let inventory = storage.getInventory()
        let expectedTasksNotDeleted = [inventory[0]]
        let expectedTasksDeleted = [inventory[1], inventory[2], inventory[3]]

        XCTAssertEqual(expectedTasksDeleted, storage.deleteTasksMemberOfGroup(groupId: givenStartOfTheGroup.string))
        XCTAssertEqual(expectedTasksNotDeleted, storage.getInventory())
    }

    func test_deleteTasksMemberOfGroup_givenTaskStartsAndBelongsToSameGroup_expectNotToGetInfiniteLoop() {
        // because task is a member of group to delete, it should be deleted by function. But because it also is the start of the group with the same name, recursion should trigger and not cause an infinite loop.
        let givenStartOfTheGroup = QueueTaskGroup.identifiedProfile(identifier: String.random)
        _ = storage.create(
            type: String.random,
            data: Data(),
            groupStart: givenStartOfTheGroup,
            blockingGroups: [givenStartOfTheGroup]
        )
        let itemsDeleted = storage.deleteTasksMemberOfGroup(groupId: givenStartOfTheGroup.string)
        XCTAssertEqual(itemsDeleted.count, 1)
        XCTAssertEqual(storage.getInventory().count, 0)
    }

    func test_deleteTasksMemberOfGroup_givenNoStartGroupPresentInInventory_expectTasksNotDeleted() {
        let givenStartOfTheGroup = QueueTaskGroup.identifiedProfile(identifier: String.random)
        let givenStartOfAnotherGroup = QueueTaskGroup.registeredPushToken(token: String.random)

        _ = storage.create(
            type: String.random,
            data: Data(),
            groupStart: nil,
            blockingGroups: [givenStartOfAnotherGroup]
        )

        _ = storage.create(
            type: String.random,
            data: Data(),
            groupStart: nil,
            blockingGroups: nil
        )

        _ = storage.create(
            type: String.random,
            data: Data(),
            groupStart: nil,
            blockingGroups: [givenStartOfAnotherGroup]
        )

        let expectedTasksNotDeleted = storage.getInventory()

        XCTAssertEqual([], storage.deleteTasksMemberOfGroup(groupId: givenStartOfTheGroup.string))
        XCTAssertEqual(expectedTasksNotDeleted, storage.getInventory())
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
#endif
