@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class QueueStorageTest: UnitTest {
    var storage: FileManagerQueueStorage!
    var implementationStorage: FileManagerQueueStorage!

    let fileStorageMock = FileStorageMock()

    override func setUp() {
        super.setUp()

        storage = FileManagerQueueStorage(siteId: testSiteId, fileStorage: fileStorageMock, jsonAdapter: jsonAdapter)
        implementationStorage = FileManagerQueueStorage(siteId: testSiteId, fileStorage: diGraph.fileStorage,
                                                        jsonAdapter: jsonAdapter)
    }

    private func getQueueTaskItem() -> QueueTaskMetadata {
        QueueTaskMetadata(taskPersistedId: String.random, taskType: .identifyProfile)
    }

    // MARK: getInventory

    func test_getInventory_givenNeverSavedInventoryBefore_expectEmpty() {
        fileStorageMock.getReturnValue = nil

        let actual = storage.getInventory()

        XCTAssertEqual(actual, [])
    }

    func test_getInventory_givenSavedPreviousInventory_expectGetExistingInventory() {
        let expected = [getQueueTaskItem()]
        fileStorageMock.getReturnValue = jsonAdapter.toJson(expected, encoder: nil)

        let actual = storage.getInventory()

        XCTAssertEqual(actual, expected)
    }

    // MARK: saveInventory

    func test_saveInventory_givenSaveSuccessful_expectTrue() {
        fileStorageMock.saveReturnValue = true

        let actual = storage.saveInventory([getQueueTaskItem()])

        XCTAssertTrue(actual)
    }

    func test_saveInventory_givenSaveUnsuccessful_expectFalse() {
        fileStorageMock.saveReturnValue = false

        let actual = storage.saveInventory([getQueueTaskItem()])

        XCTAssertFalse(actual)
    }

    // MARK: create

    func test_create_expectSaveNewTaskToStorage_expectUpdateInventory_expectTrue() {
        fileStorageMock.saveReturnValue = true

        let givenData = "hello ami!".data!
        let givenType = QueueTaskType.identifyProfile

        let actual = storage.create(type: givenType, data: givenData)

        XCTAssertEqual(fileStorageMock.saveCallsCount, 2) // create task and update inventory
        XCTAssertTrue(actual.success)
        XCTAssertEqual(actual.queueStatus, QueueStatus(queueId: testSiteId, numTasksInQueue: 1))
    }

    func test_create_givenFileStorageDoesNotSaveTask_expectDoNotUpdateInventory_expectFalse() {
        fileStorageMock.saveReturnValue = false

        let givenData = "hello ami!".data!
        let givenType = QueueTaskType.identifyProfile

        let actual = storage.create(type: givenType, data: givenData)

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
        let givenType = QueueTaskType.identifyProfile

        let actual = storage.create(type: givenType, data: givenData)

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
        let givenTask = QueueTask(storageId: String.random, type: .identifyProfile, data: "".data,
                                  runResults: QueueTaskRunResults(totalRuns: 1))
        let givenUpdatedRunResults = QueueTaskRunResults(totalRuns: givenTask.runResults.totalRuns + 1)
        fileStorageMock.getReturnValue = jsonAdapter.toJson(givenTask, encoder: nil)
        fileStorageMock.saveReturnValue = true

        let actual = storage.update(storageId: givenTask.storageId, runResults: givenUpdatedRunResults)

        XCTAssertEqual(fileStorageMock.saveCallsCount, 1)
        let actualQueueTask: QueueTask = jsonAdapter.fromJson(fileStorageMock.saveReceivedArguments!.contents,
                                                              decoder: nil)!
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
        let givenTask = QueueTask(storageId: String.random, type: .identifyProfile, data: "".data,
                                  runResults: QueueTaskRunResults(totalRuns: 1))
        fileStorageMock.getReturnValue = jsonAdapter.toJson(givenTask, encoder: nil)!

        let actual = storage.get(storageId: givenTask.storageId)

        XCTAssertNotNil(actual)
        XCTAssertEqual(actual, givenTask)
    }

    // MARK: delete

    func test_delete_expectDeleteTaskPreviouslyAdded() {
        _ = implementationStorage.create(type: .identifyProfile, data: Data())

        var inventory = implementationStorage.getInventory()
        XCTAssertEqual(inventory.count, 1)
        let givenStorageId = inventory[0].taskPersistedId
        XCTAssertNotNil(implementationStorage.get(storageId: givenStorageId))

        let actual = implementationStorage.delete(storageId: givenStorageId)

        XCTAssertTrue(actual)
        inventory = implementationStorage.getInventory()
        XCTAssertEqual(inventory.count, 0)
        XCTAssertNil(implementationStorage.get(storageId: givenStorageId))
    }
}
