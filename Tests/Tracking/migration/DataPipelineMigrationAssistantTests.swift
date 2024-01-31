@testable import CioDataPipelines
@testable import CioInternalCommon
@testable import CioTracking
import Foundation
@testable import Segment
import SharedTests
import XCTest

class DataPipelineMigrationAssistantTests: UnitTest {
    // When calling CustomerIOInstance functions in the test functions, use this `CustomerIO` instance.
    // This is a workaround until this code base contains implementation tests. There have been bugs
    // that have gone undiscovered in the code when `CustomerIO` passes a request to `DataPipelineImplementation`.
    private var customerIO: CustomerIO!
    private let profileStoreMock = ProfileStoreMock()
    private let backgroundQueueMock = QueueMock()
    private let migrationAssistantMock = DataPipelineMigrationMock()

    private var migrationAssistant: DataPipelineMigrationAssistant { diGraph.dataPipelineMigrationAssistant }
    private var queueStorage: QueueStorage { diGraph.queueStorage }

    override func setUp() {
        super.setUp()

        diGraphShared.override(value: profileStoreMock, forType: ProfileStore.self)
        diGraph.override(value: dateUtilStub, forType: DateUtil.self)
        diGraph.override(value: backgroundQueueMock, forType: Queue.self)
        diGraph.override(value: migrationAssistantMock, forType: DataPipelineMigration.self)

        customerIO = createCustomerIOInstance()
    }

    override func tearDown() {
        customerIO.clearIdentify()
        super.tearDown()
    }

    // MARK: handleQueueBacklog/getAndProcessTask

    func test_givenEmptyBacklog_expectNoTasksProcessed() {
        backgroundQueueMock.getAllStoredTasksReturnValue = []
        XCTAssertNotNil(migrationAssistant.handleQueueBacklog())
        XCTAssertEqual(backgroundQueueMock.getAllStoredTasksCallsCount, 1)
    }

    func test_givenBacklog_expectTaskProcessed() {
//        var inventory: [QueueTaskMetadata] = []
//        let givenType = QueueTaskType.identifyProfile
//        let givenTask = IdentifyProfileQueueTaskData(identifier: String.random, attributesJsonString: "null")
//        let givenQueueTaskData = jsonAdapter.toJson(givenTask)!
//        let counter = 3000
//        for _ in 1 ... counter {
//            let givenCreatedTask = (queueStorage as! FileManagerQueueStorage).create(type: givenType.rawValue, data: givenQueueTaskData, groupStart: nil, blockingGroups: nil)
//                .createdTask!
//            inventory.append(givenCreatedTask)
//        }
//
//        backgroundQueueMock.getAllStoredTasksReturnValue = inventory
//        backgroundQueueMock.getTaskDetailReturnValue = (data: givenQueueTaskData, taskType: givenType, timestamp: dateUtilStub.now)
//
//        XCTAssertNotNil(migrationAssistant.handleQueueBacklog())
//        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, counter)
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

    func test_givenAlreadyIdentifiedProfile_expectUpdateUserId() {
        let givenProfileIdentifiedInJourneys = String.random
        profileStoreMock.identifier = givenProfileIdentifiedInJourneys
        XCTAssertNotNil(migrationAssistant.handleAlreadyIdentifiedMigratedUser())
        XCTAssertEqual(migrationAssistantMock.handleAlreadyIdentifiedMigratedUserCallsCount, 1)
    }
}
