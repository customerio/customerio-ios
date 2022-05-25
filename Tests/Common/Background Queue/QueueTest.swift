@testable import Common
import Foundation
import SharedTests
import XCTest

class QueueTest: UnitTest {
    var queue: Queue!
    var implementationQueue: Queue!

    private let storageMock = QueueStorageMock()
    private let runRequestMock = QueueRunRequestMock()
    private let sdkConfigStoreMock = SdkConfigStoreMock()
    private let queueTimerMock = SingleScheduleTimerMock()

    override func setUp() {
        super.setUp()

        sdkConfigStoreMock.config = SdkConfig()

        queue = CioQueue(siteId: testSiteId, storage: storageMock, runRequest: runRequestMock, jsonAdapter: jsonAdapter,
                         logger: log, sdkConfigStore: sdkConfigStoreMock, queueTimer: queueTimerMock,
                         dateUtil: dateUtilStub)
    }

    // MARK: addTask

    func test_addTask_givenFailCreateQueueTask_expectFailStatus_expectScheduleQueueToRun() {
        storageMock.createReturnValue = (success: false,
                                         queueStatus: QueueStatus(queueId: testSiteId, numTasksInQueue: 0))
        storageMock.getInventoryReturnValue = []
        queueTimerMock.scheduleIfNotAlreadyReturnValue = true

        let actual = queue.addTask(type: String.random,
                                   data: ["foo": "bar"],
                                   groupStart: .identifiedProfile(identifier: String.random),
                                   blockingGroups: [.identifiedProfile(identifier: String.random)])

        XCTAssertEqual(actual.success, false)

        XCTAssertEqual(queueTimerMock.scheduleIfNotAlreadyCallsCount, 1)
    }

    func test_addTask_expectDoNotStartQueueIfNotMeetingCriteria_expectScheduleQueueInstead() {
        var config = SdkConfig()
        config.backgroundQueueMinNumberOfTasks = 10
        sdkConfigStoreMock.config = config
        storageMock.createReturnValue = (success: true,
                                         queueStatus: QueueStatus(queueId: testSiteId, numTasksInQueue: 1))
        storageMock.getInventoryReturnValue = [QueueTaskMetadata.random]
        queueTimerMock.scheduleIfNotAlreadyReturnValue = true

        _ = queue.addTask(type: String.random,
                          data: ["foo": "bar"],
                          groupStart: .identifiedProfile(identifier: String.random),
                          blockingGroups: [.identifiedProfile(identifier: String.random)])

        XCTAssertEqual(runRequestMock.startCallsCount, 0)

        XCTAssertEqual(queueTimerMock.scheduleIfNotAlreadyCallsCount, 1)
    }

    func test_addTask_expectStartQueueAfterSuccessfullyAddingTask_expectDoNotScheduleTimer_expectCancelTimer() {
        var config = SdkConfig()
        config.backgroundQueueMinNumberOfTasks = 1
        sdkConfigStoreMock.config = config
        storageMock.createReturnValue = (success: true,
                                         queueStatus: QueueStatus(queueId: testSiteId, numTasksInQueue: 1))
        storageMock.getInventoryReturnValue = [QueueTaskMetadata.random]

        _ = queue.addTask(type: String.random,
                          data: ["foo": "bar"],
                          groupStart: .identifiedProfile(identifier: String.random),
                          blockingGroups: [.identifiedProfile(identifier: String.random)])

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

// MARK: integration tests

#if !os(Linux) // LINUX_DISABLE_FILEMANAGER
class QueueIntegrationTest: UnitTest {
    var queue: Queue!

    private let queueRunnerMock = QueueRunnerMock()

    override func setUp() {
        super.setUp()

        diGraph.override(.queueRunner, value: queueRunnerMock, forType: QueueRunner.self)
        queue = diGraph.queue
    }

    func test_addTask_expectSuccessfullyAdded() {
        let addTaskActual = queue.addTask(type: String.random,
                                          data: ["foo": "bar"],
                                          groupStart: .identifiedProfile(identifier: String.random),
                                          blockingGroups: [.identifiedProfile(identifier: String.random)])
        XCTAssertTrue(addTaskActual.success)
        XCTAssertEqual(addTaskActual.queueStatus.numTasksInQueue, 1)
    }

    func test_addTaskThenRun_expectToRunTaskInQueueAndCallCallback() {
        queueRunnerMock.runTaskClosure = { queueTask, onComplete in
            onComplete(.success(()))
        }

        _ = queue.addTask(type: String.random,
                          data: ["foo": "bar"],
                          groupStart: .identifiedProfile(identifier: String.random),
                          blockingGroups: [.identifiedProfile(identifier: String.random)])

        let expect = expectation(description: "Expect to complete")
        queue.run {
            expect.fulfill()
        }

        waitForExpectations()
        XCTAssertEqual(queueRunnerMock.runTaskCallsCount, 1)

        let expect2 = expectation(description: "Expect to complete")
        queue.run {
            expect2.fulfill()
        }

        waitForExpectations()
        // assert that we didn't run any tasks because there were not to run
        XCTAssertEqual(queueRunnerMock.runTaskCallsCount, 1)
    }

    func test_addTaskThenRun_givenTaskFailsToRun_expectRunAgain() {
        queueRunnerMock.runTaskClosure = { queueTask, onComplete in
            onComplete(.failure(.noRequestMade(nil)))
        }

        _ = queue.addTask(type: String.random,
                          data: ["foo": "bar"],
                          groupStart: .identifiedProfile(identifier: String.random),
                          blockingGroups: [.identifiedProfile(identifier: String.random)])

        let expect = expectation(description: "Expect to complete")
        queue.run {
            expect.fulfill()
        }

        waitForExpectations()
        XCTAssertEqual(queueRunnerMock.runTaskCallsCount, 1)

        let expect2 = expectation(description: "Expect to complete")
        queue.run {
            expect2.fulfill()
        }

        waitForExpectations()
        // assert we ran tasks again because they failed first time
        XCTAssertEqual(queueRunnerMock.runTaskCallsCount, 2)
    }
}
#endif
