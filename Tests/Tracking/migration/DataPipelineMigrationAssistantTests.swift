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
        let givenQueueTaskData = jsonAdapter.toJson(givenTask)!
        let counter = 3000
        for _ in 1 ... counter {
            let givenCreatedTask = (queueStorage as! FileManagerQueueStorage).create(type: givenType.rawValue, data: givenQueueTaskData, groupStart: nil, blockingGroups: nil)
                .createdTask!
            inventory.append(givenCreatedTask)
        }

        backgroundQueueMock.getAllStoredTasksReturnValue = inventory
        backgroundQueueMock.getTaskDetailReturnValue = (data: givenQueueTaskData, taskType: givenType, timestamp: dateUtilStub.now)

        XCTAssertNotNil(migrationAssistant.handleQueueBacklog())
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, counter)
    }

    func test_givenBacklog_expectTaskRunButNotProcessedDeleted() {
        var inventory: [QueueTaskMetadata] = []
        let givenType = QueueTaskType.identifyProfile
        let givenCreatedTask = (queueStorage as! FileManagerQueueStorage).create(type: givenType.rawValue, data: Data(), groupStart: nil, blockingGroups: nil)
            .createdTask!
        inventory.append(givenCreatedTask)

        backgroundQueueMock.getAllStoredTasksReturnValue = inventory
        backgroundQueueMock.getTaskDetailReturnValue = (data: Data(), taskType: givenType, timestamp: dateUtilStub.now)

        XCTAssertNotNil(migrationAssistant.handleQueueBacklog())
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 0)
    }
}
