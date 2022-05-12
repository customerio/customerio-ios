@testable import CioTracking
@testable import Common
import Foundation
import SharedTests
import XCTest

class QueueIntegration2Test: IntegrationTest {
    private var queue: Queue!
    private var queueStorage: QueueStorage!

    override func setUp() {
        super.setUp()

        queue = diGraph.queue // Since this is an integration test, we want real instances in our test.
        queueStorage = diGraph.queueStorage
    }

    func test_givenRunQueueAndFailTasksThenRerunQueue_expectQueueRerunsAllTasksAgain() {
        let givenGroupForTasks = QueueTaskGroup.identifiedProfile(identifier: String.random)
        _ = queue.addTask(type: QueueTaskType.trackEvent.rawValue,
                          data: TrackEventQueueTaskData(identifier: String.random, attributesJsonString: ""),
                          groupStart: givenGroupForTasks)
        _ = queue.addTask(type: QueueTaskType.trackEvent.rawValue,
                          data: TrackEventQueueTaskData(identifier: String.random, attributesJsonString: ""),
                          blockingGroups: [givenGroupForTasks])

        httpRequestRunnerStub.queueNoRequestMade()

        var expect = expectation(description: "Expect to complete")
        queue.run {
            expect.fulfill()
        }
        waitForExpectations()

        XCTAssertEqual(queueStorage.getInventory().count, 2)
        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 1)

        httpRequestRunnerStub.queueSuccessfulResponse()
        httpRequestRunnerStub.queueSuccessfulResponse()

        expect = expectation(description: "Expect to complete")
        queue.run {
            expect.fulfill()
        }
        waitForExpectations()

        // expect all of tasks to run and run successfully
        XCTAssertEqual(queueStorage.getInventory().count, 0)
        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 3)
    }
}
