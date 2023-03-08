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
        let addTaskActual = queue.addTask(
            type: String.random,
            data: ["foo": "bar"],
            groupStart: .identifiedProfile(identifier: String.random),
            blockingGroups: [.identifiedProfile(identifier: String.random)]
        )
        XCTAssertTrue(addTaskActual.success)
        XCTAssertEqual(addTaskActual.queueStatus.numTasksInQueue, 1)
    }

    func test_addTaskThenRun_expectToRunTaskInQueueAndCallCallback() {
        httpRequestRunnerStub.queueSuccessfulResponse()

        _ = queue.addTask(
            type: QueueTaskType.identifyProfile.rawValue,
            data: IdentifyProfileQueueTaskData(identifier: String.random, attributesJsonString: nil),
            groupStart: .identifiedProfile(identifier: String.random),
            blockingGroups: [.identifiedProfile(identifier: String.random)]
        )

        let expect = expectation(description: "Expect to complete")
        queue.run {
            expect.fulfill()
        }

        waitForExpectations()
        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 1)

        let expect2 = expectation(description: "Expect to complete")
        queue.run {
            expect2.fulfill()
        }

        waitForExpectations()
        // assert that we didn't run any tasks because there were not to run
        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 1)
    }

    func test_givenRunQueueAndFailTasksThenRerunQueue_expectQueueRerunsAllTasksAgain() {
        let givenGroupForTasks = QueueTaskGroup.identifiedProfile(identifier: String.random)
        _ = queue.addTask(
            type: QueueTaskType.trackEvent.rawValue,
            data: TrackEventQueueTaskData(identifier: String.random, attributesJsonString: ""),
            groupStart: givenGroupForTasks
        )
        _ = queue.addTask(
            type: QueueTaskType.trackEvent.rawValue,
            data: TrackEventQueueTaskData(identifier: String.random, attributesJsonString: ""),
            blockingGroups: [givenGroupForTasks]
        )

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

    func test_givenRunQueueAndFailWith400_expectAllGroupTasksToBeDeleted() {
        let givenGroupForTasks = QueueTaskGroup.identifiedProfile(identifier: String.random)
        _ = queue.addTask(
            type: QueueTaskType.trackEvent.rawValue,
            data: TrackEventQueueTaskData(identifier: String.random, attributesJsonString: ""),
            groupStart: givenGroupForTasks
        )
        _ = queue.addTask(
            type: QueueTaskType.trackEvent.rawValue,
            data: TrackEventQueueTaskData(identifier: String.random, attributesJsonString: ""),
            blockingGroups: [givenGroupForTasks]
        )

        httpRequestRunnerStub.queueResponse(code: 400, data: "".data)

        let expect = expectation(description: "Expect to complete")
        queue.run {
            expect.fulfill()
        }
        waitForExpectations()

        XCTAssertEqual(queueStorage.getInventory().count, 0)
        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 1)
    }

    func test_givenRunQueueAndFailWith400_expectNon400TasksNotToBeDeleted() {
        let givenIdentifier = String.random
        let givenToken = String.random

        let givenIdentifyGroupForTasks = QueueTaskGroup.identifiedProfile(identifier: givenIdentifier)
        let givenRegisterGroupForTasks = QueueTaskGroup.registeredPushToken(token: givenToken)

        let queueTaskData = RegisterPushNotificationQueueTaskData(
            profileIdentifier: givenIdentifier,
            attributesJsonString: nil
        )

        _ = queue.addTask(
            type: QueueTaskType.identifyProfile.rawValue,
            data: IdentifyProfileQueueTaskData(identifier: givenIdentifier, attributesJsonString: nil),
            groupStart: givenRegisterGroupForTasks,
            blockingGroups: [givenIdentifyGroupForTasks]
        )

        _ = queue.addTask(
            type: QueueTaskType.registerPushToken.rawValue,
            data: queueTaskData,
            groupStart: givenRegisterGroupForTasks,
            blockingGroups: [givenIdentifyGroupForTasks]
        )

        _ = queue.addTask(
            type: QueueTaskType.trackPushMetric.rawValue,
            data: MetricRequest(
                deliveryId: String.random,
                event: Metric.opened,
                deviceToken: givenToken,
                timestamp: Date()
            ),
            blockingGroups: [givenRegisterGroupForTasks]
        )

        httpRequestRunnerStub.queueResponse(code: 400, data: "".data)

        let expect = expectation(description: "Expect to complete")
        queue.run {
            expect.fulfill()
        }
        waitForExpectations()

        XCTAssertEqual(queueStorage.getInventory().count, 0)
        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 1)
    }
    #endif
}
