@testable import CioInternalCommon
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class CustomerIOImplementationTest: UnitTest {
    private var implementation: CustomerIOImplementation!
    // When calling CustomerIOInstance functions in the test functions, use this `CustomerIO` instance.
    // This is a workaround until this code base contains implementation tests. There have been bugs
    // that have gone undiscovered in the code when `CustomerIO` passes a request to `CustomerIOImplementation`.
    private var customerIO: CustomerIO!

    private let backgroundQueueMock = QueueMock()
    private let profileStoreMock = ProfileStoreMock()
    private let hooksMock = HooksManagerMock()
    private let profileIdentifyHookMock = ProfileIdentifyHookMock()
    private let deviceAttributesMock = DeviceAttributesProviderMock()
    private let globalDataStoreMock = GlobalDataStoreMock()
    private let deviceInfoMock = DeviceInfoMock()

    override func setUp() {
        super.setUp()

        diGraph.override(value: backgroundQueueMock, forType: Queue.self)
        diGraph.override(value: profileStoreMock, forType: ProfileStore.self)
        diGraph.override(value: hooksMock, forType: HooksManager.self)
        diGraph.override(value: deviceAttributesMock, forType: DeviceAttributesProvider.self)
        diGraph.override(value: globalDataStoreMock, forType: GlobalDataStore.self)
        diGraph.override(value: deviceInfoMock, forType: DeviceInfo.self)

        hooksMock.underlyingProfileIdentifyHooks = [profileIdentifyHookMock]

        implementation = CustomerIOImplementation(diGraph: diGraph)
        customerIO = CustomerIO(implementation: implementation, diGraph: diGraph)
    }

    // MARK: identify

    // testing `identify()` with request body. Will make an integration test for all `identify()` functions
    // but copy/paste identify unit tests not needed since only 1 function has logic in it.
    //
    // NOTE: At this time, the `CustomerIOHttpTest` is that integration test. After refactoring the code
    // to make the DI graph work as intended and the http request runner is in the graph we can make
    // integration tests with a mocked request runner.

    func test_identify_expectSetNewProfileInDeviceStorage() {
        let givenIdentifier = String.random
        backgroundQueueMock.addTaskReturnValue = (
            success: true,
            queueStatus: QueueStatus.successAddingSingleTask
        )

        XCTAssertNil(profileStoreMock.identifier)

        customerIO.identify(identifier: givenIdentifier)

        XCTAssertEqual(profileStoreMock.identifier, givenIdentifier)
    }

    func test_identify_expectAddTaskBackgroundQueue() {
        let givenIdentifier = String.random
        let givenBody = ["first_name": "Dana"]

        backgroundQueueMock.addTaskReturnValue = (
            success: true,
            queueStatus: QueueStatus.successAddingSingleTask
        )

        customerIO.identify(identifier: givenIdentifier, body: givenBody)

        XCTAssertEqual(backgroundQueueMock.addTaskCallsCount, 1)
        XCTAssertEqual(backgroundQueueMock.addTaskReceivedArguments?.type, QueueTaskType.identifyProfile.rawValue)

        let actualQueueTaskData = backgroundQueueMock.addTaskReceivedArguments?.data
            .value as? IdentifyProfileQueueTaskData

        XCTAssertEqual(actualQueueTaskData?.identifier, givenIdentifier)
        XCTAssertEqual(actualQueueTaskData?.attributesJsonString, jsonAdapter.toJsonString(givenBody))
    }

    func test_identify_givenPreviouslyIdentifiedCustomer_expectRunHooks_expectDeleteDeviceToken() {
        let givenIdentifier = String.random
        let givenPreviouslyIdentifiedProfile = String.random
        let givenDeviceToken = String.random
        globalDataStoreMock.underlyingPushDeviceToken = givenDeviceToken
        profileStoreMock.identifier = givenPreviouslyIdentifiedProfile
        backgroundQueueMock.addTaskReturnValue = (
            success: true,
            queueStatus: QueueStatus.successAddingSingleTask
        )

        customerIO.identify(identifier: givenIdentifier)

        XCTAssertEqual(profileIdentifyHookMock.beforeIdentifiedProfileChangeCallsCount, 1)
        XCTAssertEqual(profileIdentifyHookMock.profileIdentifiedCallsCount, 1)

        XCTAssertEqual(backgroundQueueMock.deviceTokensDeleted.count, 1)
        XCTAssertEqual(backgroundQueueMock.deviceTokensDeleted, [givenDeviceToken])
    }

    func test_identify_givenProfileAlreadyIdentified_expectDoNotRunHooks_expectDoNotDeleteDeviceToken() {
        let givenIdentifier = String.random
        let givenPreviouslyIdentifiedProfile = givenIdentifier
        profileStoreMock.identifier = givenPreviouslyIdentifiedProfile
        backgroundQueueMock.addTaskReturnValue = (
            success: true,
            queueStatus: QueueStatus.successAddingSingleTask
        )

        customerIO.identify(identifier: givenIdentifier)

        XCTAssertFalse(hooksMock.mockCalled)

        XCTAssertTrue(backgroundQueueMock.deviceTokensDeleted.isEmpty)
    }

    func test_identify_givenNoProfilePreviouslyIdentified_expectRunHooks() {
        let givenIdentifier = String.random
        profileStoreMock.identifier = nil
        backgroundQueueMock.addTaskReturnValue = (
            success: true,
            queueStatus: QueueStatus.successAddingSingleTask
        )

        customerIO.identify(identifier: givenIdentifier)

        XCTAssertEqual(hooksMock.profileIdentifyHooksGetCallsCount, 1)
        XCTAssertEqual(profileIdentifyHookMock.profileIdentifiedCallsCount, 1)
    }

    func test_identify_givenEmptyIdentifier_givenNoProfilePreviouslyIdentified_expectRequestIgnored() {
        let givenIdentifier = ""
        profileStoreMock.identifier = nil

        customerIO.identify(identifier: givenIdentifier)

        XCTAssertFalse(hooksMock.mockCalled)
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

        XCTAssertFalse(hooksMock.mockCalled)
        XCTAssertTrue(backgroundQueueMock.deviceTokensDeleted.isEmpty)
        XCTAssertEqual(profileStoreMock.identifier, givenPreviouslyIdentifiedProfile)
    }

    // MARK: clearIdentify

    func test_clearIdentify_givenNoPreviouslyIdentifiedCustomer_expectDoNotRunHooks_expectStorageSetNil() {
        profileStoreMock.identifier = nil

        customerIO.clearIdentify()

        XCTAssertFalse(hooksMock.mockCalled)
        XCTAssertNil(profileStoreMock.identifier)
    }

    func test_clearIdentify_givenPreviouslyIdentifiedCustomer_expectRunHooks_expectStorageSetNil() {
        let givenIdentifier = String.random
        profileStoreMock.identifier = givenIdentifier

        customerIO.clearIdentify()

        XCTAssertEqual(hooksMock.profileIdentifyHooksGetCallsCount, 1)
        XCTAssertEqual(profileIdentifyHookMock.beforeProfileStoppedBeingIdentifiedCallsCount, 1)

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

    func test_registerDeviceToken_givenCustomerIdentified_expectAddTaskToQueue_expectStoreDeviceToken() {
        let givenDeviceToken = String.random
        let givenIdentifier = String.random
        let givenDefaultAttributes = ["foo": "bar"]
        profileStoreMock.identifier = givenIdentifier
        deviceInfoMock.underlyingOsName = "iOS"
        backgroundQueueMock.addTaskReturnValue = (success: true, queueStatus: QueueStatus.successAddingSingleTask)
        deviceAttributesMock.getDefaultDeviceAttributesClosure = { onComplete in
            onComplete(givenDefaultAttributes)
        }

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
}
