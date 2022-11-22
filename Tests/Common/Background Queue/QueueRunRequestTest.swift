@testable import Common
import Foundation
import SharedTests
import XCTest

class QueueRunRequestTest: UnitTest {
    private var runRequest: QueueRunRequest!

    private let runnerMock = QueueRunnerMock()
    private let storageMock = QueueStorageMock()
    private let requestManagerMock = QueueRequestManagerMock()
    // Class is similar to a util class and doesn't add value to be mocked.
    private var queryRunner: QueueQueryRunner {
        diGraph.queueQueryRunner
    }

    override func setUp() {
        super.setUp()

        runRequest = CioQueueRunRequest(
            runner: runnerMock,
            storage: storageMock,
            requestManager: requestManagerMock,
            logger: log,
            queryRunner: queryRunner
        )
    }

    // our indictor if run request is running the queue
    private var didStartARun: Bool {
        storageMock.getInventoryCalled && requestManagerMock.requestCompleteCalled
    }

    // MARK: start

    func test_start_givenAlreadyRunningARequest_expectDoNotStartNewRun() {
        requestManagerMock.startRequestReturnValue = true

        runRequest.start {}

        XCTAssertFalse(didStartARun)
    }

    func test_start_givenNotAlreadyRunningRequest_expectStartNewRun() {
        requestManagerMock.startRequestReturnValue = false
        storageMock.getInventoryReturnValue = []

        runRequest.start {}

        XCTAssertTrue(didStartARun)
        XCTAssertFalse(runnerMock.runTaskCalled)
    }

    func test_start_givenRunTaskSuccess_expectDeleteTask() {
        requestManagerMock.startRequestReturnValue = false
        let givenQueueTask = QueueTask.random
        let givenStorageId = givenQueueTask.storageId
        storageMock.getReturnValue = givenQueueTask
        var inventory = [
            QueueTaskMetadata.random.taskPersistedIdSet(givenStorageId)
        ]
        storageMock.getInventoryReturnValue = inventory
        runnerMock.runTaskClosure = { _, onComplete in
            inventory.removeFirst()
            onComplete(.success(()))
        }
        storageMock.deleteReturnValue = true

        runRequest.start {}

        XCTAssertTrue(didStartARun)
        XCTAssertEqual(storageMock.deleteCallsCount, 1)
        XCTAssertEqual(storageMock.deleteReceivedArguments, givenStorageId)
        XCTAssertEqual(requestManagerMock.requestCompleteCallsCount, 1)
    }

    func test_start_givenRunTaskFailure_expectDontDeleteTask_expectUpdateTask() {
        requestManagerMock.startRequestReturnValue = false
        let givenQueueTask = QueueTask.random
        let givenStorageId = givenQueueTask.storageId
        storageMock.getReturnValue = givenQueueTask
        var inventory = [
            QueueTaskMetadata.random.taskPersistedIdSet(givenStorageId)
        ]
        storageMock.getInventoryReturnValue = inventory
        runnerMock.runTaskClosure = { _, onComplete in
            inventory.removeFirst()
            onComplete(.failure(.getGenericFailure()))
        }
        storageMock.updateReturnValue = true

        runRequest.start {}

        XCTAssertTrue(didStartARun)
        XCTAssertFalse(storageMock.deleteCalled)
        XCTAssertEqual(storageMock.updateCallsCount, 1)
        XCTAssertEqual(storageMock.updateReceivedArguments?.storageId, givenStorageId)
    }

    func test_start_givenTasksToRun_expectToRunTask_expectToCompleteAfterRunningAllTasks() {
        requestManagerMock.startRequestReturnValue = false
        storageMock.getReturnValue = QueueTask.random
        var inventory = [
            QueueTaskMetadata.random,
            QueueTaskMetadata.random
        ]
        storageMock.getInventoryReturnValue = inventory
        runnerMock.runTaskClosure = { _, onComplete in
            inventory.removeFirst()
            onComplete(.success(()))
        }
        storageMock.deleteReturnValue = true

        runRequest.start {}

        XCTAssertTrue(didStartARun)
        XCTAssertEqual(requestManagerMock.requestCompleteCallsCount, 1)
        XCTAssertEqual(runnerMock.runTaskCallsCount, 2)
        XCTAssertEqual(storageMock.deleteCallsCount, 2)
    }
}

class QueueRunRequestIntegrationTest: IntegrationTest {
    private var runRequest: CioQueueRunRequest!

    private let runnerMock = QueueRunnerMock()

    var queueStorage: QueueStorage {
        diGraph.queueStorage
    }

    override func setUp() {
        super.setUp()

        diGraph.override(value: runnerMock, forType: QueueRunner.self)

        runRequest = CioQueueRunRequest(
            runner: diGraph.queueRunner,
            storage: diGraph.queueStorage,
            requestManager: diGraph.queueRequestManager,
            logger: diGraph.logger,
            queryRunner: diGraph.queueQueryRunner
        )
    }

    func test_noTasksInInventory_expectRunNoTasks() {
        runRequest.start(onComplete: onComplete_expectation)
        waitForExpectations()

        XCTAssertFalse(runnerMock.runTaskCalled)
    }

    func test_given1Task_givenTasksRunSuccessfully_expectNoTasksInInventory() {
        _ = addQueueTask()
        runnerMock.setupRunAllTasksSuccessfully()

        runRequest.start(onComplete: onComplete_expectation)
        waitForExpectations()

        XCTAssertEqual(runnerMock.runTaskCallsCount, 1)
        XCTAssertTrue(queueStorage.getInventory().isEmpty)
    }

    func test_given1Task_givenTasksRunFailed_expectNoTasksLeft_expectTasksStillInInventory() {
        let givenTaskAdded = addQueueTask()
        runnerMock.setupRunAllTasksFailure()

        runRequest.start(onComplete: onComplete_expectation)
        waitForExpectations()

        XCTAssertEqual(runnerMock.runTaskCallsCount, 1)
        XCTAssertEqual(queueStorage.getInventory(), [givenTaskAdded])
    }

    func test_givenMultipleTasks_givenTasksRunSuccessfully_expectNoTasksInInventory() {
        _ = addQueueTask()
        _ = addQueueTask()
        runnerMock.setupRunAllTasksSuccessfully()

        runRequest.start(onComplete: onComplete_expectation)
        waitForExpectations()

        XCTAssertEqual(runnerMock.runTaskCallsCount, 2)
        XCTAssertTrue(queueStorage.getInventory().isEmpty)
    }

    func test_givenMultipleTasks_givenTasksRunFailed_expectNoTasksLeft_expectTasksStillInInventory() {
        let givenTask1 = addQueueTask()
        let givenTask2 = addQueueTask()
        runnerMock.setupRunAllTasksFailure()

        runRequest.start(onComplete: onComplete_expectation)
        waitForExpectations()

        XCTAssertEqual(runnerMock.runTaskCallsCount, 2)
        XCTAssertEqual(queueStorage.getInventory(), [givenTask1, givenTask2])
    }

    func test_givenMultipleTasks_givenHttpRequestsPaused_expectQuitRunEarly() {
        let givenTask1 = addQueueTask()
        let givenTask2 = addQueueTask()
        runnerMock.runTaskClosure = { _, onComplete in
            onComplete(.failure(.requestsPaused))
        }

        runRequest.start(onComplete: onComplete_expectation)
        waitForExpectations()

        XCTAssertEqual(runnerMock.runTaskCallsCount, 1) // should have only ran 1 task, quit early
        XCTAssertEqual(queueStorage.getInventory(), [givenTask1, givenTask2])
    }

    func test_givenTaskAddedDuringRun_expectToRunTaskAdded() {
        _ = addQueueTask()

        var addedNewTaskDuringRun = false
        runnerMock.runTaskClosure = { _, onComplete in
            if !addedNewTaskDuringRun {
                _ = self.addQueueTask()

                addedNewTaskDuringRun = true
            }

            onComplete(.success(()))
        }

        runRequest.start(onComplete: onComplete_expectation)
        waitForExpectations()

        XCTAssertEqual(runnerMock.runTaskCallsCount, 2)
    }
}

extension QueueRunRequestIntegrationTest {
    private func addQueueTask() -> QueueTaskMetadata {
        queueStorage.create(
            type: String.random,
            data: "".data,
            groupStart: nil,
            blockingGroups: nil
        ).createdTask!
    }
}
