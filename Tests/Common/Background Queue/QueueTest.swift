@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class QueueTest: UnitTest {
    var queue: Queue!
    var implementationQueue: Queue!
    var queueStorage: QueueStorage {
        diGraph.queueStorage
    }

    private let storageMock = QueueStorageMock()
    private let queueMock = QueueMock()
    private let runRequestMock = QueueRunRequestMock()
    private let queueTimerMock = SingleScheduleTimerMock()

    override func setUp() {
        super.setUp()

        // setting a default for tests. Call again from test function to change
        setupTest(backgroundQueueMinNumberOfTasks: sdkConfig.backgroundQueueMinNumberOfTasks)
    }

    // MARK: addTask

    func test_addTask_givenFailCreateQueueTask_expectFailStatus_expectScheduleQueueToRun() {
        storageMock.createReturnValue = CreateQueueStorageTaskResult(
            success: false,
            queueStatus: QueueStatus(queueId: testSiteId, numTasksInQueue: 0),
            createdTask: nil
        )
        storageMock.getInventoryReturnValue = []
        queueTimerMock.scheduleIfNotAlreadyReturnValue = true

        let actual = queue.addTask(
            type: String.random,
            data: ["foo": "bar"],
            groupStart: .identifiedProfile(identifier: String.random),
            blockingGroups: [.identifiedProfile(identifier: String.random)]
        )

        XCTAssertEqual(actual.success, false)

        XCTAssertEqual(queueTimerMock.scheduleIfNotAlreadyCallsCount, 1)
    }

    func test_addTask_expectDoNotStartQueueIfNotMeetingCriteria_expectScheduleQueueInstead() {
        setupTest(backgroundQueueMinNumberOfTasks: 10)
        let givenCreatedTask = QueueTaskMetadata.random
        storageMock.createReturnValue = CreateQueueStorageTaskResult(
            success: true,
            queueStatus: QueueStatus(queueId: testSiteId, numTasksInQueue: 1),
            createdTask: givenCreatedTask
        )
        storageMock.getInventoryReturnValue = [givenCreatedTask]
        queueTimerMock.scheduleIfNotAlreadyReturnValue = true

        _ = queue.addTask(
            type: String.random,
            data: ["foo": "bar"],
            groupStart: .identifiedProfile(identifier: String.random),
            blockingGroups: [.identifiedProfile(identifier: String.random)]
        )

        XCTAssertEqual(runRequestMock.startCallsCount, 0)

        XCTAssertEqual(queueTimerMock.scheduleIfNotAlreadyCallsCount, 1)
    }

    func test_addTask_expectStartQueueAfterSuccessfullyAddingTask_expectDoNotScheduleTimer_expectCancelTimer() {
        setupTest(backgroundQueueMinNumberOfTasks: 1)
        let givenCreatedTask = QueueTaskMetadata.random
        storageMock.createReturnValue = CreateQueueStorageTaskResult(
            success: true,
            queueStatus: QueueStatus(queueId: testSiteId, numTasksInQueue: 1),
            createdTask: givenCreatedTask
        )
        storageMock.getInventoryReturnValue = [givenCreatedTask]

        _ = queue.addTask(
            type: String.random,
            data: ["foo": "bar"],
            groupStart: .identifiedProfile(identifier: String.random),
            blockingGroups: [.identifiedProfile(identifier: String.random)]
        )

        XCTAssertEqual(runRequestMock.startCallsCount, 1)

        XCTAssertFalse(queueTimerMock.scheduleIfNotAlreadyCalled)
        XCTAssertEqual(queueTimerMock.cancelCallsCount, 1)
    }

    // MARK: run

    func test_run_expectStartRunRequest() {
        runRequestMock.startClosure = { onComplete in
            onComplete()
        }

        let expect = expectation(description: "Expect to complete")
        queue.run {
            expect.fulfill()
        }

        waitForExpectations()

        XCTAssertEqual(runRequestMock.startCallsCount, 1)
    }

    // MARK: getAllStoredTasks

    func test_givenMultipleTasks_expectTaskMetaData() {
        let inventory = [
            QueueTaskMetadata.random,
            QueueTaskMetadata.random
        ]
        storageMock.getInventoryReturnValue = inventory

        XCTAssertEqual(queue.getAllStoredTasks(), inventory)
    }

    func test_givenNoTasks_expectNoMetaData() {
        storageMock.getInventoryReturnValue = []
        XCTAssertEqual(queue.getAllStoredTasks(), [])
    }

    // MARK: deleteProcessedTask

    func test_givenTaskMetaData_expectDeleteTask() {
        let givenType = QueueTaskType.identifyProfile.rawValue
        let givenData = String.random.data!
        let givenCreatedTask = queueStorage.create(type: givenType, data: givenData, groupStart: nil, blockingGroups: nil)
            .createdTask!
        storageMock.deleteReturnValue = true
        XCTAssertNotNil(queue.deleteProcessedTask(givenCreatedTask))
        XCTAssertEqual(storageMock.deleteCallsCount, 1)
    }

    // MARK: getTaskDetail

    func test_givenTask_expectTaskDetail() {
        let givenType = QueueTaskType.identifyProfile
        let givenData = String.random.data!
        let givenCreatedTask = queueStorage.create(type: givenType.rawValue, data: givenData, groupStart: nil, blockingGroups: nil)
            .createdTask!
        let givenIdentifyTask = IdentifyProfileQueueTaskData(identifier: String.random, attributesJsonString: "null")
        let givenQueueTaskData = jsonAdapter.toJson(givenIdentifyTask)!
        let givenQueueTask = QueueTask(storageId: .random, type: givenType.rawValue, data: givenQueueTaskData, runResults: QueueTaskRunResults(totalRuns: 0))

        queueMock.getTaskDetailReturnValue = (data: givenQueueTaskData, taskType: givenType)
        storageMock.getReturnValue = givenQueueTask

        XCTAssertNotNil(queue.getTaskDetail(givenCreatedTask))
        XCTAssertEqual(queue.getTaskDetail(givenCreatedTask)?.data, givenQueueTaskData)
        XCTAssertEqual(queue.getTaskDetail(givenCreatedTask)?.taskType, givenType)
    }

    func test_givenTaskNotFoundInStorage_expectNil() {
        let givenType = QueueTaskType.identifyProfile
        let givenData = String.random.data!
        let givenCreatedTask = queueStorage.create(type: givenType.rawValue, data: givenData, groupStart: nil, blockingGroups: nil)
            .createdTask!
        XCTAssertNil(queue.getTaskDetail(givenCreatedTask))
    }

    func test_givenTaskWithInValidTaskType_expectNil() {
        let givenCreatedTask = queueStorage.create(type: String.random, data: String.random.data, groupStart: nil, blockingGroups: nil)
            .createdTask!
        XCTAssertNil(queue.getTaskDetail(givenCreatedTask))
    }
}

extension QueueTest {
    func setupTest(backgroundQueueMinNumberOfTasks: Int) {
        super.setUp(modifySdkConfig: { config in
            config.backgroundQueueMinNumberOfTasks = backgroundQueueMinNumberOfTasks
        })

        queue = CioQueue(
            storage: storageMock,
            runRequest: runRequestMock,
            jsonAdapter: jsonAdapter,
            logger: log,
            sdkConfig: sdkConfig,
            queueTimer: queueTimerMock,
            dateUtil: dateUtilStub
        )
    }
}
