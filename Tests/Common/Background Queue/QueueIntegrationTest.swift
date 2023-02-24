@testable import CioTracking
@testable import Common
import Foundation
import SharedTests
import XCTest

class QueueIntegrationTest: IntegrationTest {
    private var queue: Queue!
    private var queueStorage: QueueStorage!

    override func setUp() {
        super.setUp()

        queue = diGraph.queue // Since this is an integration test, we want real instances in our test.
        queueStorage = diGraph.queueStorage
    }

    #if !os(Linux) // LINUX_DISABLE_FILEMANAGER
    func test_addTask_expectSuccessfullyAdded() {
        let expect = expectation(description: "Expected to finish async operation")

        queue.addTask(
            type: String.random,
            data: ["foo": "bar"],
            groupStart: .identifiedProfile(identifier: String.random),
            blockingGroups: [.identifiedProfile(identifier: String.random)]
        ) { addTaskActual in
            XCTAssertTrue(addTaskActual.success)
            XCTAssertEqual(addTaskActual.queueStatus.numTasksInQueue, 1)

            expect.fulfill()
        }

        waitForExpectations()
    }

    func test_addTaskThenRun_expectToRunTaskInQueueAndCallCallback() {
        httpRequestRunnerStub.queueSuccessfulResponse()

        let expectToAddTask = expectation(description: "Expected to add task")
        queue.addTask(
            type: QueueTaskType.identifyProfile.rawValue,
            data: IdentifyProfileQueueTaskData(identifier: String.random, attributesJsonString: nil),
            groupStart: .identifiedProfile(identifier: String.random),
            blockingGroups: [.identifiedProfile(identifier: String.random)]
        ) { _ in
            expectToAddTask.fulfill()
        }

        waitForExpectations()

        let expect = expectation(description: "Expect to run queue")
        queue.run {
            expect.fulfill()
        }

        waitForExpectations()
        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 1)

        let expect2 = expectation(description: "Expect to run queue")
        queue.run {
            expect2.fulfill()
        }

        waitForExpectations()
        // assert that we didn't run any tasks because there were none to run
        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 1)
    }

    func test_givenRunQueueAndFailTasksThenRerunQueue_expectQueueRerunsAllTasksAgain() {
        let givenGroupForTasks = QueueTaskGroup.identifiedProfile(identifier: String.random)

        let expectToAddTasks = expectation(description: "Expect to add tasks")
        expectToAddTasks.expectedFulfillmentCount = 2
        queue.addTask(
            type: QueueTaskType.trackEvent.rawValue,
            data: TrackEventQueueTaskData(identifier: String.random, attributesJsonString: ""),
            groupStart: givenGroupForTasks
        ) { _ in
            expectToAddTasks.fulfill()
        }
        queue.addTask(
            type: QueueTaskType.trackEvent.rawValue,
            data: TrackEventQueueTaskData(identifier: String.random, attributesJsonString: ""),
            blockingGroups: [givenGroupForTasks]
        ) { _ in
            expectToAddTasks.fulfill()
        }
        waitForExpectations()

        httpRequestRunnerStub.queueNoRequestMade()

        var expect = expectation(description: "Expect to run queue")
        queue.run {
            expect.fulfill()
        }
        waitForExpectations()

        XCTAssertEqual(queueStorage.getInventory().count, 2)
        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 1)

        httpRequestRunnerStub.queueSuccessfulResponse()
        httpRequestRunnerStub.queueSuccessfulResponse()

        expect = expectation(description: "Expect to run queue")
        queue.run {
            expect.fulfill()
        }
        waitForExpectations()

        // expect all of tasks to run and run successfully
        XCTAssertEqual(queueStorage.getInventory().count, 0)
        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 3)
    }
    #endif
}
