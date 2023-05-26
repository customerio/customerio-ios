@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class QueueRunRequestTest: UnitTest {
    private var runRequest: CioQueueRunRequest!

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
            queryRunner: queryRunner,
            threadUtil: threadUtilStub
        )

        // Boilerplate defaults:

        // Setup storage to successfully update and delete by default. Override in test function to test other behaviors.
        storageMock.updateReturnValue = true
        storageMock.deleteReturnValue = true

        // Not already running a queue run request. When you want to start a new one, start it.
        requestManagerMock.startRequestReturnValue = false
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

        runRequest.start {}

        XCTAssertTrue(didStartARun)
        XCTAssertEqual(storageMock.deleteCallsCount, 1)
        XCTAssertEqual(storageMock.deleteReceivedArguments, givenStorageId)
        XCTAssertEqual(requestManagerMock.requestCompleteCallsCount, 1)
    }

    func test_start_givenRunTaskFailure_expectDontDeleteTask_expectUpdateTask() {
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

        runRequest.start {}

        XCTAssertTrue(didStartARun)
        XCTAssertFalse(storageMock.deleteCalled)
        XCTAssertEqual(storageMock.updateCallsCount, 1)
        XCTAssertEqual(storageMock.updateReceivedArguments?.storageId, givenStorageId)
    }

    func test_start_givenTasksToRun_expectToRunTask_expectToCompleteAfterRunningAllTasks() {
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

        runRequest.start {}

        XCTAssertTrue(didStartARun)
        XCTAssertEqual(requestManagerMock.requestCompleteCallsCount, 1)
        XCTAssertEqual(runnerMock.runTaskCallsCount, 2)
        XCTAssertEqual(storageMock.deleteCallsCount, 2)
    }

    // MARK: runTasks

    // runTasks() performs async operations inside of it. A stackoverflow/infinite loop can occur if these async operations do not run in sequential order.
    func test_runTasks_expectAsyncOperationsToPerformSequentially() {
        // Events, in order, that are expected to happen
        let expectGetInventoryTask1 = expectation(description: "expect to ask for item 1 from inventory")
        let finishRunningTask1 = expectation(description: "expect task 1 to begin running")
        let expectGetInventoryTask2 = expectation(description: "expect to ask for item 2 from inventory")
        let finishRunningTask2 = expectation(description: "expect task 2 to begin running")
        let expectGetInventoryTask3 = expectation(description: "expect to ask for item 3 from inventory")
        let finishRunningTask3 = expectation(description: "expect task 3 to begin running")

        var inventory = [
            QueueTaskMetadata.random.taskPersistedIdSet(.random),
            QueueTaskMetadata.random.taskPersistedIdSet(.random),
            QueueTaskMetadata.random.taskPersistedIdSet(.random)
        ]

        storageMock.getInventoryClosure = {
            switch inventory.count {
            case 3: expectGetInventoryTask1.fulfill()
            case 2: expectGetInventoryTask2.fulfill()
            case 1: expectGetInventoryTask3.fulfill()
            default: break
            }

            return inventory
        }

        runnerMock.runTaskClosure = { _, onComplete in
            switch inventory.count {
            case 3: finishRunningTask1.fulfill()
            case 2: finishRunningTask2.fulfill()
            case 1: finishRunningTask3.fulfill()
            default: break
            }

            self.runAfterDelay(seconds: 0.5) { // simulate a network call in running a task
                // task is done! Delete task from the inventory since it is now done.
                inventory.removeFirst()
                onComplete(.success(()))
            }
        }
        storageMock.getReturnValue = QueueTask.random

        runRequest.runTasks()

        waitForExpectations(for: [
            expectGetInventoryTask1,
            finishRunningTask1,
            expectGetInventoryTask2,
            finishRunningTask2,
            expectGetInventoryTask3,
            finishRunningTask3
        ], enforceOrder: true)
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
            queryRunner: diGraph.queueQueryRunner,
            threadUtil: threadUtilStub
        )
    }

    func test_noTasksInInventory_expectRunNoTasks() {
        runRequest.start(onComplete: onCompleteExpectation)
        waitForExpectations()

        XCTAssertFalse(runnerMock.runTaskCalled)
    }

    func test_given1Task_givenTasksRunSuccessfully_expectNoTasksInInventory() {
        _ = addQueueTask()
        runnerMock.setupRunAllTasksSuccessfully()

        runRequest.start(onComplete: onCompleteExpectation)
        waitForExpectations()

        XCTAssertEqual(runnerMock.runTaskCallsCount, 1)
        XCTAssertTrue(queueStorage.getInventory().isEmpty)
    }

    func test_given1Task_givenTasksRunFailed_expectNoTasksLeft_expectTasksStillInInventory() {
        let givenTaskAdded = addQueueTask()
        runnerMock.setupRunAllTasksFailure()

        runRequest.start(onComplete: onCompleteExpectation)
        waitForExpectations()

        XCTAssertEqual(runnerMock.runTaskCallsCount, 1)
        XCTAssertEqual(queueStorage.getInventory(), [givenTaskAdded])
    }

    func test_givenMultipleTasks_givenTasksRunSuccessfully_expectNoTasksInInventory() {
        _ = addQueueTask()
        _ = addQueueTask()
        runnerMock.setupRunAllTasksSuccessfully()

        runRequest.start(onComplete: onCompleteExpectation)
        waitForExpectations()

        XCTAssertEqual(runnerMock.runTaskCallsCount, 2)
        XCTAssertTrue(queueStorage.getInventory().isEmpty)
    }

    func test_givenMultipleTasks_givenTasksRunFailed_expectNoTasksLeft_expectTasksStillInInventory() {
        let givenTask1 = addQueueTask()
        let givenTask2 = addQueueTask()
        runnerMock.setupRunAllTasksFailure()

        runRequest.start(onComplete: onCompleteExpectation)
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

        runRequest.start(onComplete: onCompleteExpectation)
        waitForExpectations()

        XCTAssertEqual(runnerMock.runTaskCallsCount, 1) // should have only ran 1 task, quit early
        XCTAssertEqual(queueStorage.getInventory(), [givenTask1, givenTask2])
    }

    func test_given400Response_expectToDeleteTask() {
        _ = addQueueTask()
        _ = addQueueTask()

        runnerMock.runTaskClosure = { _, onComplete in
            onComplete(.failure(.badRequest400(apiMessage: "")))
        }

        runRequest.start(onComplete: onCompleteExpectation)
        waitForExpectations()

        XCTAssertEqual(runnerMock.runTaskCallsCount, 2)
        XCTAssertTrue(queueStorage.getInventory().isEmpty)
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

        runRequest.start(onComplete: onCompleteExpectation)
        waitForExpectations()

        XCTAssertEqual(runnerMock.runTaskCallsCount, 2)
        XCTAssertTrue(queueStorage.getInventory().isEmpty)
    }
}

extension QueueRunRequestIntegrationTest {
    private func addQueueTask(groupStart: QueueTaskGroup? = nil, blockingGroup: [QueueTaskGroup]? = nil) -> QueueTaskMetadata {
        queueStorage.create(
            type: String.random,
            data: "".data,
            groupStart: groupStart,
            blockingGroups: blockingGroup
        ).createdTask!
    }
}
