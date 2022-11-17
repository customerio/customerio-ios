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

    // MARK: getInventory

    func test_getInventory_givenNeverSavedInventoryBefore_expectEmpty() {
        fileStorageMock.getReturnValue = nil

        let actual = storage.getInventory()

        XCTAssertEqual(actual, [])
    }

    func test_getInventory_givenSavedPreviousInventory_expectGetExistingInventory() {
        let expected = [QueueTaskMetadata.random]
        fileStorageMock.getReturnValue = jsonAdapter.toJson(expected, encoder: nil)

        let actual = storage.getInventory()

        XCTAssertEqual(actual, expected)
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

    func test_create_expectSaveNewTaskToStorage_expectUpdateInventory_expectTrue() {
        fileStorageMock.saveReturnValue = true

        let givenData = "hello ami!".data!
        let givenType = String.random

        let actual = storage.create(
            type: givenType,
            data: givenData,
            groupStart: .identifiedProfile(identifier: String.random),
            blockingGroups: [.identifiedProfile(identifier: String.random)]
        )

        XCTAssertEqual(fileStorageMock.saveCallsCount, 2) // create task and update inventory
        XCTAssertTrue(actual.success)
        XCTAssertEqual(actual.queueStatus, QueueStatus(queueId: testSiteId, numTasksInQueue: 1))
    }

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

        XCTAssertEqual(fileStorageMock.saveCallsCount, 1) // only create task call
        XCTAssertFalse(actual.success)
        XCTAssertEqual(actual.queueStatus, QueueStatus(queueId: testSiteId, numTasksInQueue: 0))
    }

    func test_create_givenFileStorageDoesNotUpdateInventory_expectFalse() {
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

        XCTAssertEqual(fileStorageMock.saveCallsCount, 2)
        XCTAssertFalse(actual.success)
        XCTAssertEqual(actual.queueStatus, QueueStatus(queueId: testSiteId, numTasksInQueue: 0))
    }

    // MARK: update

    func test_update_givenNoTaskSaved_expectFalse() {
        fileStorageMock.getReturnValue = nil

        let actual = storage.update(storageId: String.random, runResults: QueueTaskRunResults(totalRuns: 1))

        XCTAssertFalse(actual)
    }

    func test_update_expectUpdateTaskToStorage_expectInventoryNotUpdated_expectTrue() {
        let givenTask = QueueTask(
            storageId: String.random,
            type: String.random,
            data: "".data,
            runResults: QueueTaskRunResults(totalRuns: 1)
        )
        let givenUpdatedRunResults = QueueTaskRunResults(totalRuns: givenTask.runResults.totalRuns + 1)
        fileStorageMock.getReturnValue = jsonAdapter.toJson(givenTask, encoder: nil)
        fileStorageMock.saveReturnValue = true

        let actual = storage.update(storageId: givenTask.storageId, runResults: givenUpdatedRunResults)

        XCTAssertEqual(fileStorageMock.saveCallsCount, 1)
        let actualQueueTask: QueueTask = jsonAdapter.fromJson(
            fileStorageMock.saveReceivedArguments!.contents,
            decoder: nil
        )!
        let actualRunResults = actualQueueTask.runResults
        XCTAssertEqual(actualRunResults, givenUpdatedRunResults)
        XCTAssertTrue(actual)
    }

    // MARK: get

    func test_get_givenNoTaskInStorage_expectNil() {
        fileStorageMock.getReturnValue = nil

        XCTAssertNil(storage.get(storageId: String.random))
    }

    func test_get_givenTaskInStorage_expectGetSavedTask() {
        let givenTask = QueueTask(
            storageId: String.random,
            type: String.random,
            data: "".data,
            runResults: QueueTaskRunResults(totalRuns: 1)
        )
        fileStorageMock.getReturnValue = jsonAdapter.toJson(givenTask, encoder: nil)!

        let actual = storage.get(storageId: givenTask.storageId)

        XCTAssertNotNil(actual)
        XCTAssertEqual(actual, givenTask)
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
#endif
