@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class QueueRunRequestTest: UnitTest {
    private var runRequest: QueueRunRequest!

    private let runnerMock = QueueRunnerMock()
    private let storageMock = QueueStorageMock()
    private let requestManagerMock = QueueRequestManagerMock()

    override func setUp() {
        super.setUp()

        runRequest = CioQueueRunRequest(runner: runnerMock, storage: storageMock, requestManger: requestManagerMock,
                                        logger: log)
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
            QueueTaskItem(taskPersistedId: givenStorageId, taskType: .identifyProfile)
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
            QueueTaskItem(taskPersistedId: givenStorageId, taskType: .identifyProfile)
        ]
        storageMock.getInventoryReturnValue = inventory
        runnerMock.runTaskClosure = { _, onComplete in
            inventory.removeFirst()
            onComplete(.failure(.notInitialized))
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
            QueueTaskItem(taskPersistedId: String.random, taskType: .identifyProfile),
            QueueTaskItem(taskPersistedId: String.random, taskType: .identifyProfile)
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
