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
        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: Data(), taskType: givenType, timestamp: dateUtilStub.now)
        backgroundQueueMock.getAllStoredTasksReturnValue = []

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

    func test_givenIdentifyProfileWithEmptyBody_expectTaskRunAndProcessedDeleted() {
        let givenType = QueueTaskType.identifyProfile

        let givenCreatedTask = QueueTaskMetadata.random

        let trackDeliveryMetricData = IdentifyProfileQueueTaskData(identifier: String.random, attributesJsonString: "")

        guard let jsonData = try? JSONEncoder().encode(trackDeliveryMetricData) else {
            XCTFail("Failed to create task data")
            return
        }

        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: jsonData, taskType: givenType, timestamp: dateUtilStub.now)

        XCTAssertNotNil(migrationAssistant.getAndProcessTask(for: givenCreatedTask, siteId: testSiteId))
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 1)
    }

    func test_givenIdentifyProfileWithoutBody_expectTaskRunAndProcessedDeleted() {
        let givenType = QueueTaskType.identifyProfile

        let givenCreatedTask = QueueTaskMetadata.random

        let trackDeliveryMetricData = IdentifyProfileQueueTaskData(identifier: String.random, attributesJsonString: nil)

        guard let jsonData = try? JSONEncoder().encode(trackDeliveryMetricData) else {
            XCTFail("Failed to create task data")
            return
        }

        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: jsonData, taskType: givenType, timestamp: dateUtilStub.now)

        XCTAssertNotNil(migrationAssistant.getAndProcessTask(for: givenCreatedTask, siteId: testSiteId))
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 1)
    }

    func test_givenIdentifyProfileWithBody_expectTaskRunAndProcessedDeleted() {
        let givenType = QueueTaskType.identifyProfile
        let identifyProfileData = IdentifyProfileQueueTaskData(identifier: String.random, attributesJsonString: "{\"foo\": \"bar\"}")

        guard let jsonData = try? JSONEncoder().encode(identifyProfileData) else {
            XCTFail("Failed to create task data")
            return
        }

        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: jsonData, taskType: givenType, timestamp: dateUtilStub.now)

        let givenCreatedTask = QueueTaskMetadata.random

        XCTAssertNotNil(migrationAssistant.getAndProcessTask(for: givenCreatedTask, siteId: testSiteId))
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 1)
    }

    func test_givenTrackDeliveryMetric_expectTaskRunAndProcessedDeleted() {
        let givenType = QueueTaskType.trackDeliveryMetric

        let givenCreatedTask = QueueTaskMetadata.random

        let trackDeliveryMetricData = TrackDeliveryEventRequestBody(type: .inApp, payload: DeliveryPayload(deliveryId: String.random, event: .clicked, timestamp: dateUtilStub.now, metaData: ["foo": "bar"]))

        guard let jsonData = try? JSONEncoder().encode(trackDeliveryMetricData) else {
            XCTFail("Failed to create task data")
            return
        }

        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: jsonData, taskType: givenType, timestamp: dateUtilStub.now)

        XCTAssertNotNil(migrationAssistant.getAndProcessTask(for: givenCreatedTask, siteId: testSiteId))
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 1)
    }

    func test_givenTrackDeliveryMetric_expectTaskFailToProcess() {
        let givenType = QueueTaskType.trackDeliveryMetric

        let givenCreatedTask = QueueTaskMetadata.random

        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: Data(), taskType: givenType, timestamp: dateUtilStub.now)

        XCTAssertNotNil(migrationAssistant.getAndProcessTask(for: givenCreatedTask, siteId: testSiteId))
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 0)
    }

    func test_givenTrackEvent_expectTaskRunAndProcessedDeleted() {
        let givenType = QueueTaskType.trackEvent

        let givenCreatedTask = QueueTaskMetadata.random

        let trackEventAttributedJSON = TrackEventTypeForAnalytics(type: .event, name: String.random, timestamp: dateUtilStub.now)
        let trackEventData = TrackEventQueueTaskData(identifier: String.random, attributesJsonString: jsonAdapter.toJsonString(trackEventAttributedJSON)!)

        guard let jsonData = try? JSONEncoder().encode(trackEventData) else {
            XCTFail("Failed to create task data")
            return
        }

        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: jsonData, taskType: givenType, timestamp: dateUtilStub.now)

        XCTAssertNotNil(migrationAssistant.getAndProcessTask(for: givenCreatedTask, siteId: testSiteId))
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 1)
    }

    func test_givenScreenTrackEvent_expectTaskRunAndProcessedDeleted() {
        let givenType = QueueTaskType.trackEvent

        let givenCreatedTask = QueueTaskMetadata.random

        let trackEventAttributedJSON = TrackEventTypeForAnalytics(type: .screen, name: String.random, timestamp: dateUtilStub.now)
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

        let givenCreatedTask = QueueTaskMetadata.random

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

        let givenCreatedTask = QueueTaskMetadata.random

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

        let givenCreatedTask = QueueTaskMetadata.random

        let trackPushMetricData = MetricRequest(deliveryId: String.random, event: .opened, deviceToken: String.random, timestamp: dateUtilStub.now)

        guard let jsonData = try? JSONEncoder().encode(trackPushMetricData) else {
            XCTFail("Failed to create task data")
            return
        }

        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: jsonData, taskType: givenType, timestamp: dateUtilStub.now)

        XCTAssertNotNil(migrationAssistant.getAndProcessTask(for: givenCreatedTask, siteId: testSiteId))
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 1)
    }

    // MARK: Cases that do not process tasks

    func test_givenInvalidTrackDeliveryMetric_expectTaskNotProcessed() {
        let givenType = QueueTaskType.trackDeliveryMetric
        let givenCreatedTask = QueueTaskMetadata.random
        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: Data(), taskType: givenType, timestamp: dateUtilStub.now)

        XCTAssertNotNil(migrationAssistant.getAndProcessTask(for: givenCreatedTask, siteId: testSiteId))
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 0)
    }

    func test_givenInvalidTrackEvent_expectTaskNotProcessed() {
        let givenType = QueueTaskType.trackEvent
        let givenCreatedTask = QueueTaskMetadata.random
        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: Data(), taskType: givenType, timestamp: dateUtilStub.now)

        XCTAssertNotNil(migrationAssistant.getAndProcessTask(for: givenCreatedTask, siteId: testSiteId))
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 0)
    }

    func test_givenInvalidTrackTypeEvent_expectTaskNotProcessed() {
        let givenType = QueueTaskType.trackEvent

        let givenCreatedTask = QueueTaskMetadata.random

        let trackEventData = TrackEventQueueTaskData(identifier: String.random, attributesJsonString: "")

        guard let jsonData = try? JSONEncoder().encode(trackEventData) else {
            XCTFail("Failed to create task data")
            return
        }
        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: jsonData, taskType: givenType, timestamp: dateUtilStub.now)
        XCTAssertNotNil(migrationAssistant.getAndProcessTask(for: givenCreatedTask, siteId: testSiteId))
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 0)
    }

    func test_givenInvalidRegisterPushToken_expectTaskNotProcessed() {
        let givenType = QueueTaskType.registerPushToken

        let givenCreatedTask = QueueTaskMetadata.random

        // When data is not found in the task
        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: Data(), taskType: givenType, timestamp: dateUtilStub.now)
        XCTAssertNotNil(migrationAssistant.getAndProcessTask(for: givenCreatedTask, siteId: testSiteId))
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 0)

        // When data is found but attributes are null
        let pushTokenTaskDataWithNilAttributesString = RegisterPushNotificationQueueTaskData(profileIdentifier: String.random, attributesJsonString: nil)

        guard let jsonData = try? JSONEncoder().encode(pushTokenTaskDataWithNilAttributesString) else {
            XCTFail("Failed to create task data")
            return
        }
        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: jsonData, taskType: givenType, timestamp: dateUtilStub.now)

        XCTAssertNotNil(migrationAssistant.getAndProcessTask(for: givenCreatedTask, siteId: testSiteId))
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 0)

        // When data is found but attributes are invalid
        let pushTokenTaskDataWithEmptyJsonString = RegisterPushNotificationQueueTaskData(profileIdentifier: String.random, attributesJsonString: "")

        guard let jsonData = try? JSONEncoder().encode(pushTokenTaskDataWithEmptyJsonString) else {
            XCTFail("Failed to create task data")
            return
        }
        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: jsonData, taskType: givenType, timestamp: dateUtilStub.now)

        XCTAssertNotNil(migrationAssistant.getAndProcessTask(for: givenCreatedTask, siteId: testSiteId))
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 0)

        // When device attribute is invalid
        let pushTokenTaskDataWithInvalidJsonString = RegisterPushNotificationQueueTaskData(profileIdentifier: String.random, attributesJsonString: "{\"foo\": \"bar\"}")

        guard let jsonData = try? JSONEncoder().encode(pushTokenTaskDataWithInvalidJsonString) else {
            XCTFail("Failed to create task data")
            return
        }
        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: jsonData, taskType: givenType, timestamp: dateUtilStub.now)

        XCTAssertNotNil(migrationAssistant.getAndProcessTask(for: givenCreatedTask, siteId: testSiteId))
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 0)
    }

    func test_givenInvalidDeletePushToken_expectTaskNotProcessed() {
        let givenType = QueueTaskType.deletePushToken

        let givenCreatedTask = QueueTaskMetadata.random

        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: Data(), taskType: givenType, timestamp: dateUtilStub.now)

        XCTAssertNotNil(migrationAssistant.getAndProcessTask(for: givenCreatedTask, siteId: testSiteId))
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 0)
    }

    func test_InvalidTrackPushMetric_expectTaskNotProcessed() {
        let givenType = QueueTaskType.trackPushMetric

        let givenCreatedTask = QueueTaskMetadata.random
        backgroundQueueMock.getTaskDetailReturnValue = TaskDetail(data: Data(), taskType: givenType, timestamp: dateUtilStub.now)

        XCTAssertNotNil(migrationAssistant.getAndProcessTask(for: givenCreatedTask, siteId: testSiteId))
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 0)
    }
}
