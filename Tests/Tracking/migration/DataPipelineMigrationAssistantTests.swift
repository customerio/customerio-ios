@testable import CioDataPipelines
@testable import CioInternalCommon
@testable import CioTracking
import Foundation
@testable import Segment
import SharedTests
import XCTest

class DataPipelineMigrationAssistantTests: UnitTest {
    private let backgroundQueueMock = QueueMock()

    private var migrationAssistant: DataPipelineMigrationAssistant { diGraph.dataPipelineMigrationAssistant }
    private var queueStorage: QueueStorage { diGraph.queueStorage }

    override func setUpDependencies() {
        super.setUpDependencies()

        diGraphShared.override(value: backgroundQueueMock, forType: Queue.self)
        diGraph.override(value: backgroundQueueMock, forType: Queue.self)
    }

    // MARK: handleQueueBacklog/getAndProcessTask

    func test_givenEmptyBacklog_expectNoTasksProcessed() {
        backgroundQueueMock.getAllStoredTasksReturnValue = []
        XCTAssertNotNil(migrationAssistant.handleQueueBacklog())
        XCTAssertEqual(backgroundQueueMock.getAllStoredTasksCallsCount, 1)
    }

    func test_givenBacklog_expectTaskProcessed() {
        var inventory: [QueueTaskMetadata] = []
        let givenType = QueueTaskType.identifyProfile
        let givenTask = IdentifyProfileQueueTaskData(identifier: String.random, attributesJsonString: "null")

        guard let givenQueueTaskData = jsonAdapter.toJson(givenTask) else {
            XCTFail("Failed to convert givenTask to JSON")
            return
        }

        guard let fileManagerQueueStorage = queueStorage as? FileManagerQueueStorage else {
            XCTFail("queueStorage could not be cast to FileManagerQueueStorage")
            return
        }

        let counter = 3000
        for _ in 1 ... counter {
            guard let givenCreatedTask = fileManagerQueueStorage.create(type: givenType.rawValue, data: givenQueueTaskData, groupStart: nil, blockingGroups: nil).createdTask else {
                XCTFail("Failed to create task")
                return
            }
            inventory.append(givenCreatedTask)
        }

        backgroundQueueMock.getAllStoredTasksReturnValue = inventory
        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: givenQueueTaskData, taskType: givenType, timestamp: dateUtilStub.now)

        XCTAssertNotNil(migrationAssistant.handleQueueBacklog())
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, counter)
    }

    func test_givenBacklog_expectTaskRunButNotProcessedDeleted() {
        var inventory: [QueueTaskMetadata] = []
        let givenType = QueueTaskType.identifyProfile

        guard let fileManagerQueueStorage = queueStorage as? FileManagerQueueStorage else {
            XCTFail("queueStorage could not be cast to FileManagerQueueStorage")
            return
        }

        guard let givenCreatedTask = fileManagerQueueStorage.create(type: givenType.rawValue, data: Data(), groupStart: nil, blockingGroups: nil).createdTask else {
            XCTFail("Failed to create task")
            return
        }

        inventory.append(givenCreatedTask)

        backgroundQueueMock.getAllStoredTasksReturnValue = inventory
        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: Data(), taskType: givenType, timestamp: dateUtilStub.now)

        XCTAssertNotNil(migrationAssistant.handleQueueBacklog())
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 0)
    }
}
