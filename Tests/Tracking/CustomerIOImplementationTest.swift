@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class CustomerIOImplementationTest: UnitTest {
    private var customerIO: CustomerIOImplementation!

    private var backgroundQueueMock = QueueMock()
    private var profileStoreMock = ProfileStoreMock()

    override func setUp() {
        super.setUp()

        diGraph.override(.queue, value: backgroundQueueMock, forType: Queue.self)
        diGraph.override(.profileStore, value: profileStoreMock, forType: ProfileStore.self)

        customerIO = CustomerIOImplementation(siteId: diGraph.siteId)
    }

    // MARK: config

    func test_config_givenModifyConfig_expectSetConfigOnInstance() {
        let givenTrackingApiUrl = String.random

        customerIO.config {
            $0.trackingApiUrl = givenTrackingApiUrl
        }

        let sdkConfig = diGraph.sdkConfigStore.config

        XCTAssertEqual(sdkConfig.trackingApiUrl, givenTrackingApiUrl)
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
        backgroundQueueMock.addTaskReturnValue = (success: true,
                                                  queueStatus: QueueStatus(queueId: testSiteId, numTasksInQueue: 1))

        XCTAssertNil(profileStoreMock.identifier)

        customerIO.identify(identifier: givenIdentifier)

        XCTAssertEqual(profileStoreMock.identifier, givenIdentifier)
    }

    func test_identify_expectAddTaskBackgroundQueue() {
        let givenIdentifier = String.random
        let givenBody = ["first_name": "Dana"]

        backgroundQueueMock.addTaskReturnValue = (success: true,
                                                  queueStatus: QueueStatus(queueId: testSiteId, numTasksInQueue: 1))

        customerIO.identify(identifier: givenIdentifier, body: givenBody)

        XCTAssertEqual(backgroundQueueMock.addTaskCallsCount, 1)
        XCTAssertEqual(backgroundQueueMock.addTaskReceivedArguments?.type, QueueTaskType.identifyProfile.rawValue)

        let actualQueueTaskData = backgroundQueueMock.addTaskReceivedArguments?.data
            .value as? IdentifyProfileQueueTaskData

        XCTAssertEqual(actualQueueTaskData?.identifier, givenIdentifier)
        XCTAssertEqual(actualQueueTaskData?.attributesJsonString, jsonAdapter.toJsonString(givenBody))
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
        backgroundQueueMock.addTaskReturnValue = (success: true,
                                                  queueStatus: QueueStatus(queueId: testSiteId, numTasksInQueue: 1))

        customerIO.track(name: String.random, data: givenData)

        XCTAssertEqual(backgroundQueueMock.addTaskCallsCount, 1)
        XCTAssertEqual(backgroundQueueMock.addTaskReceivedArguments?.type, QueueTaskType.trackEvent.rawValue)

        let actualQueueTaskData = backgroundQueueMock.addTaskReceivedArguments?.data.value as? TrackEventQueueTaskData

        XCTAssertEqual(actualQueueTaskData?.identifier, givenIdentifier)
        XCTAssertTrue(actualQueueTaskData!.attributesJsonString.contains(jsonAdapter.toJsonString(givenData)!))
    }
}
