@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
@testable import Segment
import SharedTests
import XCTest

class DataPipelineInteractionTests: UnitTest {
    // When calling CustomerIOInstance functions in the test functions, use this `CustomerIO` instance.
    // This is a workaround until this code base contains implementation tests. There have been bugs
    // that have gone undiscovered in the code when `CustomerIO` passes a request to `DataPipelineImplementation`.
    private var customerIO: CustomerIO!
    private var analytics: Analytics!
    private var outputReader: OutputReaderPlugin!

    private let deviceInfoMock = DeviceInfoMock()
    private let globalDataStoreMock = GlobalDataStoreMock()

    override func setUp() {
        super.setUp()

        // override for both shared and simple graph. Data Pipeline module primarily relies on the shared graph,
        // while some older classes from tracking still utilize the simple graph.
        diGraphShared.override(value: deviceInfoMock, forType: DeviceInfo.self)
        diGraph.override(value: deviceInfoMock, forType: DeviceInfo.self)
        diGraphShared.override(value: globalDataStoreMock, forType: GlobalDataStore.self)
        diGraph.override(value: globalDataStoreMock, forType: GlobalDataStore.self)

        let moduleConfig = DataPipelineConfigOptions.Factory.create(writeKey: "test")
        let implementation = DataPipelineImplementation(diGraph: diGraphShared, moduleConfig: moduleConfig)

        DataPipeline.setupSharedTestInstance(implementation: implementation, config: moduleConfig)
        customerIO = CustomerIO(implementation: implementation, diGraph: diGraph)

        // setting up analytics for testing
        analytics = implementation.analytics
        // OutputReaderPlugin helps validating interactions with analytics
        outputReader = OutputReaderPlugin()
        analytics.add(plugin: outputReader)
        // wait for analytics queue to start emitting events
        waitUntilStarted(analytics: analytics)
    }

    override func tearDown() {
        customerIO.clearIdentify()
        super.tearDown()
    }

    // MARK: identify

    // testing `identify()` with request body. Will make an integration test for all `identify()` functions
    // but copy/paste identify unit tests not needed since only 1 function has logic in it.

    func test_identify_expectSetNewProfileWithoutAttributes() {
        let givenIdentifier = String.random

        XCTAssertNil(analytics.userId)

        customerIO.identify(identifier: givenIdentifier)

        XCTAssertEqual(analytics.userId, givenIdentifier)
        XCTAssertEqual(analytics.traits()?.count, 0)
    }

    func test_identify_expectSetNewProfileWithAttributes() {
        let givenIdentifier = String.random
        let givenBody: [String: Any] = ["first_name": "Dana", "age": 30]

        customerIO.identify(identifier: givenIdentifier, body: givenBody)

        let identifyEvent: IdentifyEvent? = outputReader.lastEvent as? IdentifyEvent
        XCTAssertEqual(analytics.userId, givenIdentifier)

        let traits = identifyEvent?.traits?.dictionaryValue
        XCTAssertEqual(traits?.count, 2)
        XCTAssertEqual(traits?["first_name"] as? String, (givenBody["first_name"] as! String))
        XCTAssertEqual(traits?["age"] as? Int, (givenBody["age"] as! Int))
    }

    // MARK: device token

    func test_identify_givenPreviouslyIdentifiedProfile_expectDeleteDeviceToken() {
        let givenIdentifier = String.random
        let givenPreviouslyIdentifiedProfile = String.random
        let givenDeviceToken = String.random

        configureDeviceInfo()
        globalDataStoreMock.underlyingPushDeviceToken = givenDeviceToken
        customerIO.identify(identifier: givenPreviouslyIdentifiedProfile)

        customerIO.identify(identifier: givenIdentifier)

        let deletedEvents = outputReader.events.filterDeviceDeleted()
        XCTAssertEqual(deletedEvents.count, 1)
        XCTAssertEqual(deletedEvents[0].getDeviceToken(), givenDeviceToken)
    }

    func test_identify_givenProfileReidentified_expectDoNotDeleteDeviceToken() {
        let givenIdentifier = String.random
        let givenPreviouslyIdentifiedProfile = givenIdentifier
        let givenDeviceToken = String.random

        configureDeviceInfo()
        globalDataStoreMock.underlyingPushDeviceToken = givenDeviceToken
        customerIO.identify(identifier: givenPreviouslyIdentifiedProfile)

        customerIO.identify(identifier: givenIdentifier)

        let deletedEvents = outputReader.events.filterDeviceDeleted()
        XCTAssertEqual(deletedEvents.count, 0)
    }

    func test_identify_givenProfileNotIdentified_expectNoDeviceEvents() {
        let givenDeviceToken = String.random

        configureDeviceInfo()
        customerIO.registerDeviceToken(givenDeviceToken)

        let events = outputReader.events
        let createdEvents = events.filterDeviceCreated()
        XCTAssertEqual(createdEvents.count, 0)
        let deletedEvents = events.filterDeviceDeleted()
        XCTAssertEqual(deletedEvents.count, 0)
    }

    func test_identify_givenEmptyIdentifier_givenNoProfilePreviouslyIdentified_expectRequestIgnored() {
        let givenIdentifier = ""
        profileStoreMock.identifier = nil

        customerIO.identify(identifier: givenIdentifier)

        XCTAssertNil(profileStoreMock.identifier)
    }

    func test_identify_givenEmptyIdentifier_givenProfileAlreadyIdentified_expectDoNotRunHooks_expectDoNotDeleteDeviceToken() {
        let givenIdentifier = ""
        let givenPreviouslyIdentifiedProfile = String.random
        profileStoreMock.identifier = givenPreviouslyIdentifiedProfile

        backgroundQueueMock.addTaskReturnValue = (
            success: true,
            queueStatus: QueueStatus.successAddingSingleTask
        )

        customerIO.identify(identifier: givenIdentifier)

        XCTAssertTrue(backgroundQueueMock.deviceTokensDeleted.isEmpty)
        XCTAssertEqual(profileStoreMock.identifier, givenPreviouslyIdentifiedProfile)
    }

    // MARK: clearIdentify

    func test_clearIdentify_givenNoPreviouslyIdentifiedCustomer_expectDoNotRunHooks_expectStorageSetNil() {
        profileStoreMock.identifier = nil

        customerIO.clearIdentify()

        XCTAssertNil(profileStoreMock.identifier)
    }

    func test_clearIdentify_givenPreviouslyIdentifiedCustomer_expectRunHooks_expectStorageSetNil() {
        let givenIdentifier = String.random
        profileStoreMock.identifier = givenIdentifier

        customerIO.clearIdentify()

        XCTAssertNil(profileStoreMock.identifier)
    }

    func test_clearIdentify_expectAbleToGetIdentifierFromStorageInHooks() {
        let givenIdentifier = String.random
        profileStoreMock.identifier = givenIdentifier
        let expect = expectation(description: "Expect to call hook")
        profileIdentifyHookMock.beforeProfileStoppedBeingIdentifiedClosure = { actualOldIdentifier in
            XCTAssertNotNil(self.profileStoreMock.identifier)
            XCTAssertEqual(self.profileStoreMock.identifier, actualOldIdentifier)

            expect.fulfill()
        }

        customerIO.clearIdentify()

        waitForExpectations()

        XCTAssertNil(profileStoreMock.identifier)
    }

    // MARK: track

    func test_track_givenNoProfileIdentified_expectIgnoreRequest() {
        profileStoreMock.identifier = nil

        customerIO.track(name: String.random)

        XCTAssertFalse(backgroundQueueMock.addTaskCalled)
    }

    func test_track_expectAddTaskToQueue_expectAssociateEventWithCurrentlyIdentifiedProfile() {
        let givenIdentifier = String.random
        let givenData = ["first_name": "Dana"]
        profileStoreMock.identifier = givenIdentifier
        backgroundQueueMock.addTaskReturnValue = (
            success: true,
            queueStatus: QueueStatus.successAddingSingleTask
        )

        customerIO.track(name: String.random, data: givenData)

        XCTAssertEqual(backgroundQueueMock.addTaskCallsCount, 1)
        XCTAssertEqual(backgroundQueueMock.addTaskReceivedArguments?.type, QueueTaskType.trackEvent.rawValue)

        let actualQueueTaskData = backgroundQueueMock.addTaskReceivedArguments?.data.value as? TrackEventQueueTaskData

        XCTAssertEqual(actualQueueTaskData?.identifier, givenIdentifier)
        XCTAssertTrue(actualQueueTaskData!.attributesJsonString.contains(jsonAdapter.toJsonString(givenData)!))
    }

    // Tests bug found in: https://github.com/customerio/customerio-ios/issues/134#issuecomment-1028090193
    // If `{"data": null, ...}`, that's a bug that results in HTTP request returning a 400.
    // We want instead: `{"data": {}, ...}`
    func test_track_givenDataNil_expectSaveEmptyRequestData() {
        let givenIdentifier = String.random
        profileStoreMock.identifier = givenIdentifier
        backgroundQueueMock.addTaskReturnValue = (
            success: true,
            queueStatus: QueueStatus.successAddingSingleTask
        )

        let data: EmptyRequestBody? = nil
        customerIO.track(name: String.random, data: data)

        XCTAssertEqual(backgroundQueueMock.addTaskCallsCount, 1)
        XCTAssertEqual(backgroundQueueMock.addTaskReceivedArguments?.type, QueueTaskType.trackEvent.rawValue)

        let actualQueueTaskData = backgroundQueueMock.addTaskReceivedArguments?.data.value as? TrackEventQueueTaskData

        XCTAssertEqual(actualQueueTaskData?.identifier, givenIdentifier)
        XCTAssertTrue(actualQueueTaskData!.attributesJsonString.contains(#"{"data":{}"#))
        XCTAssertFalse(actualQueueTaskData!.attributesJsonString.contains("null"))
    }

    // MARK: screen

    func test_screen_givenNoProfileIdentified_expectIgnoreRequest_expectDoNotCallHooks() {
        profileStoreMock.identifier = nil

        customerIO.screen(name: String.random)

        XCTAssertFalse(backgroundQueueMock.addTaskCalled)
        XCTAssertFalse(hooksMock.mockCalled)
    }

    func test_screen_expectAddTaskToQueue_expectCorrectDataAddedToQueue_expectCallHooks() {
        let givenIdentifier = String.random
        let givenData = ["first_name": "Dana"]
        profileStoreMock.identifier = givenIdentifier
        backgroundQueueMock.addTaskReturnValue = (
            success: true,
            queueStatus: QueueStatus.successAddingSingleTask
        )

        customerIO.screen(name: String.random, data: givenData)

        XCTAssertEqual(backgroundQueueMock.addTaskCallsCount, 1)
        XCTAssertEqual(backgroundQueueMock.addTaskReceivedArguments?.type, QueueTaskType.trackEvent.rawValue)

        let actualQueueTaskData = backgroundQueueMock.addTaskReceivedArguments?.data.value as? TrackEventQueueTaskData

        XCTAssertEqual(actualQueueTaskData?.identifier, givenIdentifier)
        XCTAssertTrue(actualQueueTaskData!.attributesJsonString.contains(jsonAdapter.toJsonString(givenData)!))
        XCTAssertTrue(hooksMock.screenViewHooksCalled)
        XCTAssertEqual(hooksMock.screenViewHooksGetCallsCount, 1)
    }

    // MARK: registerDeviceToken

    func test_registerDeviceToken_givenNoCustomerIdentified_expectNoAddingToQueue_expectStoreDeviceToken() {
        let givenDeviceToken = String.random
        profileStoreMock.identifier = nil

        customerIO.registerDeviceToken(givenDeviceToken)

        XCTAssertFalse(backgroundQueueMock.mockCalled)
        XCTAssertEqual(globalDataStoreMock.pushDeviceToken, givenDeviceToken)
    }

    func test_registeredDeviceToken_givenDeviceTokenAlreadySaved_expectToken() {
        let givenDeviceToken = String.random
        customerIO.registerDeviceToken(givenDeviceToken)

        XCTAssertEqual(customerIO.registeredDeviceToken, givenDeviceToken)
    }

    func test_registeredDeviceToken_givenDeviceTokenNotSaved_expectNil() {
        XCTAssertNil(customerIO.registeredDeviceToken)
    }

    func test_registerDeviceToken_givenCustomerIdentified_expectAddTaskToQueue_expectStoreDeviceToken() {
        let givenDeviceToken = String.random
        let givenIdentifier = String.random
        let givenDefaultAttributes = ["foo": "bar"]
        profileStoreMock.identifier = givenIdentifier
        deviceInfoMock.underlyingOsName = "iOS"
        backgroundQueueMock.addTaskReturnValue = (success: true, queueStatus: QueueStatus.successAddingSingleTask)
//        deviceAttributesMock.getDefaultDeviceAttributesClosure = { onComplete in
//            onComplete(givenDefaultAttributes)
//        }

        customerIO.registerDeviceToken(givenDeviceToken)

        XCTAssertEqual(backgroundQueueMock.addTaskCallsCount, 1)
        XCTAssertEqual(backgroundQueueMock.addTaskReceivedArguments?.type, QueueTaskType.registerPushToken.rawValue)
        let actualQueueTaskData = backgroundQueueMock.addTaskReceivedArguments!.data
            .value as? RegisterPushNotificationQueueTaskData

        XCTAssertNotNil(actualQueueTaskData)
        XCTAssertEqual(actualQueueTaskData?.profileIdentifier, givenIdentifier)
        let expectedJsonString = jsonAdapter.toJsonString(RegisterDeviceRequest(
            device:
            Device(
                token: givenDeviceToken,
                platform: "iOS",
                lastUsed: dateUtilStub
                    .givenNow,
                attributes: StringAnyEncodable(logger: log, givenDefaultAttributes)
            )
        ))
        XCTAssertEqual(actualQueueTaskData?.attributesJsonString, expectedJsonString)

        XCTAssertEqual(globalDataStoreMock.pushDeviceToken, givenDeviceToken)
    }

    func test_registerDeviceToken_givenNoOsNameAvailable_expectNoAddingToQueue() {
        let givenDeviceToken = String.random
        deviceInfoMock.underlyingOsName = nil
        profileStoreMock.identifier = String.random

        customerIO.registerDeviceToken(givenDeviceToken)

        XCTAssertFalse(backgroundQueueMock.mockCalled)
        XCTAssertEqual(globalDataStoreMock.pushDeviceToken, givenDeviceToken)
    }

    // MARK: deleteDeviceToken

    func test_deleteDeviceToken_givenNoCustomerIdentified_givenNoExistingPushToken_expectNoAddingTaskToQueue() {
        globalDataStoreMock.pushDeviceToken = nil
        profileStoreMock.identifier = nil

        customerIO.deleteDeviceToken()

        XCTAssertFalse(backgroundQueueMock.mockCalled)
        XCTAssertNil(globalDataStoreMock.pushDeviceToken)
    }

    func test_deleteDeviceToken_givenCustomerIdentified_givenNoExistingPushToken_expectNoAddingTaskToQueue() {
        globalDataStoreMock.pushDeviceToken = nil
        profileStoreMock.identifier = String.random

        customerIO.deleteDeviceToken()

        XCTAssertFalse(backgroundQueueMock.mockCalled)
        XCTAssertNil(globalDataStoreMock.pushDeviceToken)
    }

    func test_deleteDeviceToken_givenNoCustomerIdentified_givenExistingPushToken_expectNoAddingTaskToQueue() {
        globalDataStoreMock.pushDeviceToken = String.random
        profileStoreMock.identifier = nil

        customerIO.deleteDeviceToken()

        XCTAssertFalse(backgroundQueueMock.mockCalled)
        XCTAssertNotNil(globalDataStoreMock.pushDeviceToken)
    }

    func test_deleteDeviceToken_givenCustomerIdentified_givenExistingPushToken_expectAddTaskToQueue() {
        let givenDeviceToken = String.random
        let givenIdentifier = String.random

        globalDataStoreMock.pushDeviceToken = givenDeviceToken
        profileStoreMock.identifier = givenIdentifier
        backgroundQueueMock.addTaskReturnValue = (success: true, queueStatus: QueueStatus.successAddingSingleTask)

        customerIO.deleteDeviceToken()

        XCTAssertEqual(backgroundQueueMock.addTaskCallsCount, 1)
        XCTAssertEqual(backgroundQueueMock.addTaskReceivedArguments?.type, QueueTaskType.deletePushToken.rawValue)
        let actualQueueTaskData = backgroundQueueMock.addTaskReceivedArguments!.data
            .value as? DeletePushNotificationQueueTaskData

        XCTAssertNotNil(actualQueueTaskData)
        XCTAssertEqual(actualQueueTaskData?.profileIdentifier, givenIdentifier)
        XCTAssertEqual(actualQueueTaskData?.deviceToken, givenDeviceToken)

        XCTAssertNotNil(globalDataStoreMock.pushDeviceToken)
    }

    // MARK: trackMetric

    func test_trackMetric_expectAddTaskToQueue() {
        let givenDeliveryId = String.random
        let givenEvent = Metric.delivered
        let givenDeviceToken = String.random
        backgroundQueueMock.addTaskReturnValue = (success: true, queueStatus: QueueStatus.successAddingSingleTask)

        customerIO.trackMetric(deliveryID: givenDeliveryId, event: givenEvent, deviceToken: givenDeviceToken)

        XCTAssertEqual(backgroundQueueMock.addTaskCallsCount, 1)
        XCTAssertEqual(backgroundQueueMock.addTaskReceivedArguments?.type, QueueTaskType.trackPushMetric.rawValue)
        let actualQueueTaskData = backgroundQueueMock.addTaskReceivedArguments!.data.value as? MetricRequest

        XCTAssertNotNil(actualQueueTaskData)
        XCTAssertEqual(actualQueueTaskData?.deliveryId, givenDeliveryId)
        XCTAssertEqual(actualQueueTaskData?.event, givenEvent)
        XCTAssertEqual(actualQueueTaskData?.deviceToken, givenDeviceToken)
    }

    // MARK: handleQueueBacklog/getAndProcessTask

    func test_givenEmptyBacklog_expectNoTasksProcessed() {
        backgroundQueueMock.getAllStoredTasksReturnValue = []
        XCTAssertNotNil(implementation.handleQueueBacklog())
        XCTAssertEqual(backgroundQueueMock.getAllStoredTasksCallsCount, 1)
    }

    func test_givenBacklog_expectTaskProcessed() {
        var inventory: [QueueTaskMetadata] = []
        let givenType = QueueTaskType.identifyProfile
        let givenTask = IdentifyProfileQueueTaskData(identifier: String.random, attributesJsonString: "null")
        let givenQueueTaskData = jsonAdapter.toJson(givenTask)!
        let counter = 3000
        for _ in 1 ... counter {
            let givenCreatedTask = queueStorage.create(type: givenType.rawValue, data: givenQueueTaskData, groupStart: nil, blockingGroups: nil)
                .createdTask!
            inventory.append(givenCreatedTask)
        }

        backgroundQueueMock.getAllStoredTasksReturnValue = inventory
        backgroundQueueMock.getTaskDetailReturnValue = (data: givenQueueTaskData, taskType: givenType)

        XCTAssertNotNil(implementation.handleQueueBacklog())
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, counter)
    }

    func test_givenBacklog_expectTaskRunButNotProcessedDeleted() {
        var inventory: [QueueTaskMetadata] = []
        let givenType = QueueTaskType.identifyProfile
        let givenCreatedTask = queueStorage.create(type: givenType.rawValue, data: Data(), groupStart: nil, blockingGroups: nil)
            .createdTask!
        inventory.append(givenCreatedTask)

        backgroundQueueMock.getAllStoredTasksReturnValue = inventory
        backgroundQueueMock.getTaskDetailReturnValue = (data: Data(), taskType: givenType)

        XCTAssertNotNil(implementation.handleQueueBacklog())
        XCTAssertEqual(backgroundQueueMock.deleteProcessedTaskCallsCount, 0)
    }
}

extension DataPipelineInteractionTests {
    private func configureDeviceInfo() {
        deviceInfoMock.underlyingSdkVersion = "3.0.0"
        deviceInfoMock.underlyingCustomerAppVersion = "1.2.3"
        deviceInfoMock.underlyingDeviceLocale = String.random
        deviceInfoMock.underlyingDeviceManufacturer = String.random
        deviceInfoMock.isPushSubscribedClosure = { onComplete in
            onComplete(true)
        }
    }
}

private extension RawEvent {
    func getDeviceToken() -> String? {
        if let context = context?.dictionaryValue {
            return context[keyPath: "device.token"] as? String
        }
        return nil
    }
}

private extension [RawEvent] {
    func filterDeviceDeleted() -> [RawEvent] {
        filter { ($0 as? TrackEvent)?.event == "Device Deleted" }
    }

    func filterDeviceCreated() -> [RawEvent] {
        filter { ($0 as? TrackEvent)?.event == "Device Created or Updated" }
    }
}
