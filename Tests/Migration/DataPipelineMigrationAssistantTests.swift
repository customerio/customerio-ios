@testable import CioInternalCommon
@testable import CioTrackingMigration
import Foundation
import SharedTests
import XCTest

class DataPipelineMigrationAssistantTests: UnitTest {
    private let profileStoreMock = ProfileStoreMock()
    private let backgroundQueueMock = QueueMock()
    private let migrationHandler = DataPipelineMigrationActionMock()
    private var queueStorage: QueueStorage { diGraphShared.queueStorage }
    public var migrationAssistant: DataPipelineMigrationAssistant {
        DataPipelineMigrationAssistant(handler: migrationHandler)
    }

    override func setUpDependencies() {
        super.setUpDependencies()

        diGraphShared.override(value: profileStoreMock, forType: ProfileStore.self)
        diGraphShared.override(value: dateUtilStub, forType: DateUtil.self)
        diGraphShared.override(value: backgroundQueueMock, forType: Queue.self)
    }

    // MARK: performMigration

    // Tests that the methods are not nil and do not crash for cases
    // such as when the user id is nil or takes expected parameter
    func test_performMigration_WithAndWithoutUserId() {
        backgroundQueueMock.getAllStoredTasksReturnValue = []
        XCTAssertNotNil(migrationAssistant.performMigration(siteId: testSiteId))
    }

    // MARK: handleQueueBacklog/getAndProcessTask

    func test_givenEmptyBacklog_expectNoTasksProcessed() {
        backgroundQueueMock.getAllStoredTasksReturnValue = []
        XCTAssertNotNil(migrationAssistant.handleQueueBacklog(siteId: testSiteId))
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
        let givenType = QueueTaskType.identifyProfile

        guard let givenCreatedTask = createTaskAndStoreInInventory(forType: givenType) else {
            XCTFail("Failed to create task")
            return
        }

        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: Data(), taskType: givenType, timestamp: dateUtilStub.now)

        XCTAssertNotNil(migrationAssistant.handleQueueBacklog(siteId: testSiteId))
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 0)
    }

    func test_migrateUserId_expectMigrationCodeRunOnce() {
        // profile previously identified in SDK, before CDP migration
        let givenIdentifier = String.random
        profileStoreMock.getProfileIdReturnValue = givenIdentifier

        // CDP migration is performed for the first time in the SDK.
        XCTAssertNotNil(migrationAssistant.handleAlreadyIdentifiedMigratedUser(siteId: testSiteId))
        // deleteProfileId method is called when migration happened then
        XCTAssertEqual(profileStoreMock.deleteProfileIdCallsCount, 1)

        // Check that the migration was successful:
        // To ensure the user does not undergo the migration process again
        // after being identified on the CDP.
        // Remove the return value of identifier so that
        // the profile is not found on calling `profileStore.getProfileId(siteId: siteId)`
        profileStoreMock.getProfileIdReturnValue = nil

        XCTAssertNotNil(migrationAssistant.handleAlreadyIdentifiedMigratedUser(siteId: testSiteId))
        // Ensure that `deleteProfileIdCallsCount` is not called again
        // If the count increases then it means migration was done again
        XCTAssertEqual(profileStoreMock.deleteProfileIdCallsCount, 1)
    }

    func test_givenAlreadyIdentifiedProfile_expectNilProfileIdentifier() {
        let givenProfileIdentifiedInJourneys = String.random

        profileStoreMock.getProfileIdReturnValue = givenProfileIdentifiedInJourneys
        migrationAssistant.handleAlreadyIdentifiedMigratedUser(siteId: testSiteId)
        profileStoreMock.getProfileIdReturnValue = nil

        XCTAssertNil(profileStoreMock.getProfileId(siteId: testSiteId))
    }

    func test_givenUserOnCDPIdentified_expectNoUpdate() {
        let givenIdentifier = String.random
        migrationHandler.processAlreadyIdentifiedUser(identifier: givenIdentifier)
        XCTAssertNotNil(migrationAssistant.handleAlreadyIdentifiedMigratedUser(siteId: testSiteId))
        profileStoreMock.getProfileIdReturnValue = nil
        XCTAssertNil(profileStoreMock.getProfileId(siteId: testSiteId))
    }

    func test_givenUserOnCDPIdentified_expectMigrationCodeRunOnce() {
        let givenIdentifier = String.random
        migrationHandler.processAlreadyIdentifiedUser(identifier: givenIdentifier)
        profileStoreMock.getProfileIdReturnValue = givenIdentifier
        XCTAssertNotNil(migrationAssistant.handleAlreadyIdentifiedMigratedUser(siteId: testSiteId))
        profileStoreMock.getProfileIdReturnValue = nil

        XCTAssertNil(profileStoreMock.getProfileId(siteId: testSiteId))
        XCTAssertEqual(profileStoreMock.deleteProfileIdCallsCount, 1)

        // Re-call handleAlreadyIdentifiedMigratedUser to ensure the user does not
        // undergo the migration process again after being identified on the CDP
        // mock property `deleteProfileIdCallsCount` is called only once
        XCTAssertNotNil(migrationAssistant.handleAlreadyIdentifiedMigratedUser(siteId: testSiteId))
        XCTAssertNil(profileStoreMock.getProfileId(siteId: testSiteId))
        XCTAssertEqual(profileStoreMock.deleteProfileIdCallsCount, 1)
    }

    // MARK: getAndProcessTask

    func test_givenTrackDeliveryMetric_expectTaskRunAndProcessedDeleted() {
        let givenType = QueueTaskType.trackDeliveryMetric

        guard let givenCreatedTask = createTaskAndStoreInInventory(forType: givenType) else {
            XCTFail("Failed to create task")
            return
        }

        let trackDeliveryMetricData = TrackDeliveryEventRequestBody(type: .inApp, payload: DeliveryPayload(deliveryId: String.random, event: .clicked, timestamp: Date(), metaData: ["foo": "bar"]))

        guard let jsonData = try? JSONEncoder().encode(trackDeliveryMetricData) else {
            XCTFail("Failed to create task data")
            return
        }

        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: jsonData, taskType: givenType, timestamp: dateUtilStub.now)

        XCTAssertNotNil(migrationAssistant.getAndProcessTask(for: givenCreatedTask, siteId: testSiteId))
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 1)
    }

    func test_givenTrackEvent_expectTaskRunAndProcessedDeleted() {
        let givenType = QueueTaskType.trackEvent

        guard let givenCreatedTask = createTaskAndStoreInInventory(forType: givenType) else {
            XCTFail("Failed to create task")
            return
        }

        let trackEventAttributedJSON = TrackEventTypeForAnalytics(type: .event, name: String.random, timestamp: Date())
        let trackEventData = TrackEventQueueTaskData(identifier: String.random, attributesJsonString: jsonAdapter.toJsonString(trackEventAttributedJSON)!)

        guard let jsonData = try? JSONEncoder().encode(trackEventData) else {
            XCTFail("Failed to create task data")
            return
        }

        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: jsonData, taskType: givenType, timestamp: dateUtilStub.now)

        XCTAssertNotNil(migrationAssistant.getAndProcessTask(for: givenCreatedTask, siteId: testSiteId))
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 1)
    }

    func test_givenRegisterPushToken_expectTaskRunAndProcessedDeleted() {
        let givenType = QueueTaskType.registerPushToken

        guard let givenCreatedTask = createTaskAndStoreInInventory(forType: givenType) else {
            XCTFail("Failed to create task")
            return
        }

        let pushTokenTaskData = RegisterPushNotificationQueueTaskData(profileIdentifier: String.random, attributesJsonString: "{\"device\": {\"id\" : \"\(String.random)\", \"attributes\": {\"foo\":\"bar\"}}}")

        guard let jsonData = try? JSONEncoder().encode(pushTokenTaskData) else {
            XCTFail("Failed to create task data")
            return
        }

        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: jsonData, taskType: givenType, timestamp: dateUtilStub.now)

        XCTAssertNotNil(migrationAssistant.getAndProcessTask(for: givenCreatedTask, siteId: testSiteId))
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 1)
    }

    func test_givenDeletePushToken_expectTaskRunAndProcessedDeleted() {
        let givenType = QueueTaskType.deletePushToken

        guard let givenCreatedTask = createTaskAndStoreInInventory(forType: givenType) else {
            XCTFail("Failed to create task")
            return
        }

        let pushTokenTaskData = DeletePushNotificationQueueTaskData(profileIdentifier: String.random, deviceToken: String.random)

        guard let jsonData = try? JSONEncoder().encode(pushTokenTaskData) else {
            XCTFail("Failed to create task data")
            return
        }

        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: jsonData, taskType: givenType, timestamp: dateUtilStub.now)

        XCTAssertNotNil(migrationAssistant.getAndProcessTask(for: givenCreatedTask, siteId: testSiteId))
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 1)
    }

    func test_givenTrackPushMetric_expectTaskRunAndProcessedDeleted() {
        let givenType = QueueTaskType.trackPushMetric

        guard let givenCreatedTask = createTaskAndStoreInInventory(forType: givenType) else {
            XCTFail("Failed to create task")
            return
        }

        let trackPushMetricData = MetricRequest(deliveryId: String.random, event: .opened, deviceToken: String.random, timestamp: Date())

        guard let jsonData = try? JSONEncoder().encode(trackPushMetricData) else {
            XCTFail("Failed to create task data")
            return
        }

        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: jsonData, taskType: givenType, timestamp: dateUtilStub.now)

        XCTAssertNotNil(migrationAssistant.getAndProcessTask(for: givenCreatedTask, siteId: testSiteId))
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 1)
    }
}

extension DataPipelineMigrationAssistantTests {
    private func createTaskAndStoreInInventory(forType type: QueueTaskType) -> QueueTaskMetadata? {
        guard let fileManagerQueueStorage = queueStorage as? FileManagerQueueStorage else {
            XCTFail("queueStorage could not be cast to FileManagerQueueStorage")
            return nil
        }

        guard let givenCreatedTask = fileManagerQueueStorage.create(siteId: testSiteId, type: type.rawValue, data: Data(), groupStart: nil, blockingGroups: nil).createdTask else {
            XCTFail("Failed to create task")
            return nil
        }
        var inventory: [QueueTaskMetadata] = []
        inventory.append(givenCreatedTask)
        backgroundQueueMock.getAllStoredTasksReturnValue = inventory

        return givenCreatedTask
    }
}
