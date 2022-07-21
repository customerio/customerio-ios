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

        queue = CioQueue(
            siteId: testSiteId,
            storage: storageMock,
            runRequest: runRequestMock,
            jsonAdapter: jsonAdapter,
            logger: log,
            sdkConfigStore: sdkConfigStoreMock,
            queueTimer: queueTimerMock
        )
    }

    // MARK: addTask

    func test_addTask_givenFailCreateQueueTask_expectFailStatus_expectScheduleQueueToRun() {
        storageMock.createReturnValue = (
            success: false,
            queueStatus: QueueStatus(queueId: testSiteId, numTasksInQueue: 0)
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
        var config = SdkConfig()
        config.backgroundQueueMinNumberOfTasks = 10
        sdkConfigStoreMock.config = config
        storageMock.createReturnValue = (
            success: true,
            queueStatus: QueueStatus(queueId: testSiteId, numTasksInQueue: 1)
        )
        storageMock.getInventoryReturnValue = [QueueTaskMetadata.random]
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
        var config = SdkConfig()
        config.backgroundQueueMinNumberOfTasks = 1
        sdkConfigStoreMock.config = config
        storageMock.createReturnValue = (
            success: true,
            queueStatus: QueueStatus(queueId: testSiteId, numTasksInQueue: 1)
        )
        storageMock.getInventoryReturnValue = [QueueTaskMetadata.random]

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
