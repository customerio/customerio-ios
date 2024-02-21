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
    private let profileStoreMock = ProfileStoreMock()
    private let backgroundQueueMock = QueueMock()

    private var migrationAssistant: DataPipelineMigrationAssistant { diGraph.dataPipelineMigrationAssistant }
    private var queueStorage: QueueStorage { diGraph.queueStorage }

    override func setUpDependencies() {
        super.setUpDependencies()

        diGraph.override(value: profileStoreMock, forType: ProfileStore.self)
        diGraph.override(value: dateUtilStub, forType: DateUtil.self)
        diGraph.override(value: backgroundQueueMock, forType: Queue.self)
    }

    // MARK: handleQueueBacklog/getAndProcessTask

    func test_givenEmptyBacklog_expectNoTasksProcessed() {
        backgroundQueueMock.getAllStoredTasksReturnValue = []
        XCTAssertNotNil(migrationAssistant.handleQueueBacklog(siteId: .random))
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
            guard let givenCreatedTask = fileManagerQueueStorage.create(siteId: testSiteId, type: givenType.rawValue, data: givenQueueTaskData, groupStart: nil, blockingGroups: nil).createdTask else {
                XCTFail("Failed to create task")
                return
            }
            inventory.append(givenCreatedTask)
        }

        backgroundQueueMock.getAllStoredTasksReturnValue = inventory
        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: givenQueueTaskData, taskType: givenType, timestamp: dateUtilStub.now)

        XCTAssertNotNil(migrationAssistant.handleQueueBacklog(siteId: testSiteId))
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, counter)
    }

    func test_givenBacklog_expectTaskRunButNotProcessedDeleted() {
        var inventory: [QueueTaskMetadata] = []
        let givenType = QueueTaskType.identifyProfile

        guard let fileManagerQueueStorage = queueStorage as? FileManagerQueueStorage else {
            XCTFail("queueStorage could not be cast to FileManagerQueueStorage")
            return
        }

        guard let givenCreatedTask = fileManagerQueueStorage.create(siteId: testSiteId, type: givenType.rawValue, data: Data(), groupStart: nil, blockingGroups: nil).createdTask else {
            XCTFail("Failed to create task")
            return
        }

        inventory.append(givenCreatedTask)

        backgroundQueueMock.getAllStoredTasksReturnValue = inventory
        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: Data(), taskType: givenType, timestamp: dateUtilStub.now)

        XCTAssertNotNil(migrationAssistant.handleQueueBacklog(siteId: testSiteId))
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 0)
    }

    func test_givenAlreadyIdentifiedProfile_expectUpdateUserId() {
        let givenProfileIdentifiedInJourneys = String.random
        profileStoreMock.getProfileIdReturnValue = givenProfileIdentifiedInJourneys
        DataPipeline.shared.analytics.reset()
        XCTAssertNil(DataPipeline.shared.analytics.userId)

        migrationAssistant.handleAlreadyIdentifiedMigratedUser(siteId: testSiteId)

        XCTAssertEqual(DataPipeline.shared.analytics.userId, givenProfileIdentifiedInJourneys)
    }

    func test_givenNoIdentifiedProfile_expectNoUpdateInUserId() {
        profileStoreMock.getProfileIdReturnValue = nil

        DataPipeline.shared.analytics.reset()
        migrationAssistant.handleAlreadyIdentifiedMigratedUser(siteId: testSiteId)
        XCTAssertNil(DataPipeline.shared.analytics.userId)
    }

    func test_givenUserOnCDPIdentified_expectNoUpdate() {
        let givenIdentifier = String.random
        CustomerIO.shared.identify(userId: givenIdentifier)
        XCTAssertNotNil(migrationAssistant.handleAlreadyIdentifiedMigratedUser(siteId: testSiteId))
        XCTAssertEqual(DataPipeline.shared.analytics.userId, givenIdentifier)
    }

    func test_migrateProfileId_expectMigrationCodeRunOnce() {
        DataPipeline.shared.analytics.reset()
        // profile previously identified in SDK, before CDP migration
        let givenIdentifier = String.random
        profileStoreMock.getProfileIdReturnValue = givenIdentifier
        XCTAssertNil(DataPipeline.shared.analytics.userId)

        // CDP migration is performed for the first time in the SDK.
        migrationAssistant.handleAlreadyIdentifiedMigratedUser(siteId: testSiteId)
        // Check that the migration was successful:
        XCTAssertEqual(DataPipeline.shared.analytics.userId, givenIdentifier)
        // Update the user identifier and re-call handleAlreadyIdentifiedMigratedUser
        // to ensure the user does not undergo the migration process again
        // after being identified on the CDP
        let updatedIdentifier = String.random
        profileStoreMock.getProfileIdReturnValue = updatedIdentifier
        migrationAssistant.handleAlreadyIdentifiedMigratedUser(siteId: testSiteId)

        // We expect the CDP profile ID is the same value from the 1st migration done.
        XCTAssertEqual(DataPipeline.shared.analytics.userId, givenIdentifier)
    }
}
