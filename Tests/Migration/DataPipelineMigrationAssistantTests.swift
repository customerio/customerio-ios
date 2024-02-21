@testable import CioInternalCommon
@testable import CioTrackingMigration
import Foundation
import SharedTests
import XCTest

class DataPipelineMigrationAssistantTests: UnitTest {
    // When calling CustomerIOInstance functions in the test functions, use this `CustomerIO` instance.
    // This is a workaround until this code base contains implementation tests. There have been bugs
    // that have gone undiscovered in the code when `CustomerIO` passes a request to `DataPipelineImplementation`.
    private let profileStoreMock = ProfileStoreMock()
    private let backgroundQueueMock = QueueMock()
    private let migrationHandler = DataPipelineMigrationActionMock()
    private var queueStorage: QueueStorage { diGraph.queueStorage }
    public var migrationAssistant: DataPipelineMigrationAssistant {
        DataPipelineMigrationAssistant(handler: migrationHandler, diGraph: diGraph)
    }

    override func setUpDependencies() {
        super.setUpDependencies()

        diGraph.override(value: profileStoreMock, forType: ProfileStore.self)
        diGraph.override(value: dateUtilStub, forType: DateUtil.self)
        diGraph.override(value: backgroundQueueMock, forType: Queue.self)
    }

    // MARK: performMigration

    // Tests that the methods are not nil and do not crash for cases
    // such as when the user id is nil or takes expected parameter
    func test_performMigration_WithAndWithoutUserId() {
        backgroundQueueMock.getAllStoredTasksReturnValue = []
        XCTAssertNotNil(migrationAssistant.performMigration(for: nil))
        XCTAssertNotNil(migrationAssistant.performMigration(for: String.random))
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

    func test_migrateUserId_expectMigrationCodeRunOnce() {
        // profile previously identified in SDK, before CDP migration
        let givenIdentifier = String.random
        profileStoreMock.identifier = givenIdentifier

        // CDP migration is performed for the first time in the SDK.
        XCTAssertNotNil(migrationAssistant.handleAlreadyIdentifiedMigratedUser(for: nil))
        XCTAssertNil(profileStoreMock.identifier)

        // Check that the migration was successful:
        // Update the user identifier and re-call handleAlreadyIdentifiedMigratedUser
        // to ensure the user does not undergo the migration process again
        // after being identified on the CDP
        let updatedIdentifier = String.random
        profileStoreMock.identifier = updatedIdentifier

        XCTAssertNotNil(migrationAssistant.handleAlreadyIdentifiedMigratedUser(for: givenIdentifier))
        XCTAssertNotNil(profileStoreMock.identifier)
    }

    func test_givenAlreadyIdentifiedProfile_expectNilProfileIdentifier() {
        let givenProfileIdentifiedInJourneys = String.random
        profileStoreMock.identifier = givenProfileIdentifiedInJourneys
        migrationAssistant.handleAlreadyIdentifiedMigratedUser(for: nil)

        XCTAssertNil(profileStoreMock.identifier)
    }

    func test_givenUserOnCDPIdentified_expectNoUpdate() {
        let givenIdentifier = String.random
        migrationHandler.processAlreadyIdentifiedUser(identifier: givenIdentifier)
        XCTAssertNotNil(migrationAssistant.handleAlreadyIdentifiedMigratedUser(for: givenIdentifier))
        XCTAssertNil(profileStoreMock.identifier)
    }

    func test_givenUserOnCDPIdentified_expectMigrationCodeRunOnce() {
        let givenIdentifier = String.random
        migrationHandler.processAlreadyIdentifiedUser(identifier: givenIdentifier)
        XCTAssertNotNil(migrationAssistant.handleAlreadyIdentifiedMigratedUser(for: givenIdentifier))
        XCTAssertNil(profileStoreMock.identifier)

        // Update the user identifier and re-call handleAlreadyIdentifiedMigratedUser
        // to ensure the user does not undergo the migration process again
        // after being identified on the CDP
        let updatedIdentifier = String.random
        profileStoreMock.identifier = updatedIdentifier
        XCTAssertNotNil(migrationAssistant.handleAlreadyIdentifiedMigratedUser(for: givenIdentifier))
        XCTAssertEqual(profileStoreMock.identifier, updatedIdentifier)
    }
}
