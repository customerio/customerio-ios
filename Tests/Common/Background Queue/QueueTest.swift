@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class QueueTest: UnitTest {
    var queue: Queue!
    var implementationQueue: Queue!

    private let storageMock = QueueStorageMock()
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
