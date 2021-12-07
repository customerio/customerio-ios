@testable import CioMessagingPush
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class PushDeviceTokenRepositoryTest: UnitTest {
    private let profileStoreMock = ProfileStoreMock()
    private let queueMock = QueueMock()
    private let globalDataStoreMock = GlobalDataStoreMock()

    private var repository: PushDeviceTokenRepository!

    override func setUp() {
        super.setUp()

        diGraph.override(.profileStore, value: profileStoreMock, forType: ProfileStore.self)
        diGraph.override(.queue, value: queueMock, forType: Queue.self)
        diGraph.override(.globalDataStore, value: globalDataStoreMock, forType: GlobalDataStore.self)

        repository = CioPushDeviceTokenRepository(diTracking: diGraph)
    }

    // MARK: registerDeviceToken

    func test_registerDeviceToken_givenNoCustomerIdentified_expectNoAddingToQueue_expectStoreDeviceToken() {
        let givenDeviceToken = String.random
        profileStoreMock.identifier = nil

        repository.registerDeviceToken(givenDeviceToken)

        XCTAssertFalse(queueMock.mockCalled)
        XCTAssertEqual(globalDataStoreMock.pushDeviceToken, givenDeviceToken)
    }

    func test_registerDeviceToken_givenCustomerIdentified_expectAddTaskToQueue_expectStoreDeviceToken() {
        let givenDeviceToken = String.random
        let givenIdentifier = String.random
        profileStoreMock.identifier = givenIdentifier
        queueMock.addTaskReturnValue = (success: true, queueStatus: QueueStatus.successAddingSingleTask)

        repository.registerDeviceToken(givenDeviceToken)

        XCTAssertEqual(queueMock.addTaskCallsCount, 1)
        XCTAssertEqual(queueMock.addTaskReceivedArguments?.type, QueueTaskType.registerPushToken.rawValue)
        let actualQueueTaskData = queueMock.addTaskReceivedArguments!.data
            .value as! RegisterPushNotificationQueueTaskData
        XCTAssertEqual(actualQueueTaskData.profileIdentifier, givenIdentifier)
        XCTAssertEqual(actualQueueTaskData.deviceToken, givenDeviceToken)

        XCTAssertEqual(globalDataStoreMock.pushDeviceToken, givenDeviceToken)
    }

    // MARK: deleteDeviceToken

    func test_deleteDeviceToken_givenNoCustomerIdentified_givenNoExistingPushToken_expectNoAddingTaskToQueue_expectDeleteFromStorage(
    ) {
        globalDataStoreMock.pushDeviceToken = nil
        profileStoreMock.identifier = nil

        repository.deleteDeviceToken()

        XCTAssertFalse(queueMock.mockCalled)
        XCTAssertNil(globalDataStoreMock.pushDeviceToken)
    }

    func test_deleteDeviceToken_givenCustomerIdentified_givenNoExistingPushToken_expectNoAddingTaskToQueue_expectDeleteFromStorage(
    ) {
        globalDataStoreMock.pushDeviceToken = nil
        profileStoreMock.identifier = String.random

        repository.deleteDeviceToken()

        XCTAssertFalse(queueMock.mockCalled)
        XCTAssertNil(globalDataStoreMock.pushDeviceToken)
    }

    func test_deleteDeviceToken_givenNoCustomerIdentified_givenExistingPushToken_expectNoAddingTaskToQueue_expectDeleteFromStorage(
    ) {
        globalDataStoreMock.pushDeviceToken = String.random
        profileStoreMock.identifier = nil

        repository.deleteDeviceToken()

        XCTAssertFalse(queueMock.mockCalled)
        XCTAssertNil(globalDataStoreMock.pushDeviceToken)
    }

    func test_deleteDeviceToken_givenCustomerIdentified_givenExistingPushToken_expectAddTaskToQueue_expectDeleteFromStorage(
    ) {
        let givenDeviceToken = String.random
        let givenIdentifier = String.random

        globalDataStoreMock.pushDeviceToken = givenDeviceToken
        profileStoreMock.identifier = givenIdentifier
        queueMock.addTaskReturnValue = (success: true, queueStatus: QueueStatus.successAddingSingleTask)

        repository.deleteDeviceToken()

        XCTAssertEqual(queueMock.addTaskCallsCount, 1)
        XCTAssertEqual(queueMock.addTaskReceivedArguments?.type, QueueTaskType.deletePushToken.rawValue)
        let actualQueueTaskData = queueMock.addTaskReceivedArguments!.data.value as! DeletePushNotificationQueueTaskData
        XCTAssertEqual(actualQueueTaskData.profileIdentifier, givenIdentifier)
        XCTAssertEqual(actualQueueTaskData.deviceToken, givenDeviceToken)

        XCTAssertNil(globalDataStoreMock.pushDeviceToken)
    }
}
