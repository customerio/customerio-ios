@testable import CioMessagingPush
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class MessagingPushImplementationTest: UnitTest {
    private var mockCustomerIO = CustomerIOInstanceMock()
    private var messagingPush: MessagingPushImplementation!

    private let profileStoreMock = ProfileStoreMock()
    private let queueMock = QueueMock()
    private let globalDataStoreMock = GlobalDataStoreMock()
    private let sdkConfigStoreMock = SdkConfigStoreMock()

    override func setUp() {
        super.setUp()

        mockCustomerIO.siteId = testSiteId
        sdkConfigStoreMock.config = SdkConfig()
        messagingPush = MessagingPushImplementation(profileStore: profileStoreMock, backgroundQueue: queueMock,
                                                    globalDataStore: globalDataStoreMock, logger: log, sdkConfigStore: sdkConfigStoreMock)
    }

    // MARK: registerDeviceToken

    func test_registerDeviceToken_givenNoCustomerIdentified_expectNoAddingToQueue_expectStoreDeviceToken() {
        let givenDeviceToken = String.random
        profileStoreMock.identifier = nil

        messagingPush.registerDeviceToken(givenDeviceToken)

        XCTAssertFalse(queueMock.mockCalled)
        XCTAssertEqual(globalDataStoreMock.pushDeviceToken, givenDeviceToken)
    }

    func test_registerDeviceToken_givenCustomerIdentified_expectAddTaskToQueue_expectStoreDeviceToken() {
        let givenDeviceToken = String.random
        let givenIdentifier = String.random
        profileStoreMock.identifier = givenIdentifier
        queueMock.addTaskReturnValue = (success: true, queueStatus: QueueStatus.successAddingSingleTask)

        messagingPush.registerDeviceToken(givenDeviceToken)

        XCTAssertEqual(queueMock.addTaskCallsCount, 1)
        XCTAssertEqual(queueMock.addTaskReceivedArguments?.type, QueueTaskType.registerPushToken.rawValue)
        let actualQueueTaskData = queueMock.addTaskReceivedArguments!.data
            .value as! RegisterPushNotificationQueueTaskData
        XCTAssertEqual(actualQueueTaskData.profileIdentifier, givenIdentifier)
        XCTAssertEqual(actualQueueTaskData.deviceToken, givenDeviceToken)

        XCTAssertEqual(globalDataStoreMock.pushDeviceToken, givenDeviceToken)
    }
    
    // MARK: deleteDeviceToken

    func test_deleteDeviceToken_givenNoCustomerIdentified_givenNoExistingPushToken_expectNoAddingTaskToQueue() {
        globalDataStoreMock.pushDeviceToken = nil
        profileStoreMock.identifier = nil

        messagingPush.deleteDeviceToken()

        XCTAssertFalse(queueMock.mockCalled)
        XCTAssertNil(globalDataStoreMock.pushDeviceToken)
    }

    func test_deleteDeviceToken_givenCustomerIdentified_givenNoExistingPushToken_expectNoAddingTaskToQueue() {
        globalDataStoreMock.pushDeviceToken = nil
        profileStoreMock.identifier = String.random

        messagingPush.deleteDeviceToken()

        XCTAssertFalse(queueMock.mockCalled)
        XCTAssertNil(globalDataStoreMock.pushDeviceToken)
    }

    func test_deleteDeviceToken_givenNoCustomerIdentified_givenExistingPushToken_expectNoAddingTaskToQueue() {
        globalDataStoreMock.pushDeviceToken = String.random
        profileStoreMock.identifier = nil

        messagingPush.deleteDeviceToken()

        XCTAssertFalse(queueMock.mockCalled)
        XCTAssertNotNil(globalDataStoreMock.pushDeviceToken)
    }

    func test_deleteDeviceToken_givenCustomerIdentified_givenExistingPushToken_expectAddTaskToQueue() {
        let givenDeviceToken = String.random
        let givenIdentifier = String.random

        globalDataStoreMock.pushDeviceToken = givenDeviceToken
        profileStoreMock.identifier = givenIdentifier
        queueMock.addTaskReturnValue = (success: true, queueStatus: QueueStatus.successAddingSingleTask)

        messagingPush.deleteDeviceToken()

        XCTAssertEqual(queueMock.addTaskCallsCount, 1)
        XCTAssertEqual(queueMock.addTaskReceivedArguments?.type, QueueTaskType.deletePushToken.rawValue)
        let actualQueueTaskData = queueMock.addTaskReceivedArguments!.data.value as! DeletePushNotificationQueueTaskData
        XCTAssertEqual(actualQueueTaskData.profileIdentifier, givenIdentifier)
        XCTAssertEqual(actualQueueTaskData.deviceToken, givenDeviceToken)

        XCTAssertNotNil(globalDataStoreMock.pushDeviceToken)
    }

    // MARK: trackMetric

    func test_trackMetric_expectAddTaskToQueue() {
        let givenDeliveryId = String.random
        let givenEvent = Metric.delivered
        let givenDeviceToken = String.random
        queueMock.addTaskReturnValue = (success: true, queueStatus: QueueStatus.successAddingSingleTask)

        messagingPush.trackMetric(deliveryID: givenDeliveryId, event: givenEvent, deviceToken: givenDeviceToken)

        XCTAssertEqual(queueMock.addTaskCallsCount, 1)
        XCTAssertEqual(queueMock.addTaskReceivedArguments?.type, QueueTaskType.trackPushMetric.rawValue)
        let actualQueueTaskData = queueMock.addTaskReceivedArguments!.data.value as! MetricRequest
        XCTAssertEqual(actualQueueTaskData.deliveryId, givenDeliveryId)
        XCTAssertEqual(actualQueueTaskData.event, givenEvent)
        XCTAssertEqual(actualQueueTaskData.deviceToken, givenDeviceToken)
    }
    
    // MARK: DeviceAttributes
    func test_deviceAttributes_givenDeviceToken_expectDefaultDeviceAttributesDictionary() {
        let givenDeviceToken = String.random
        var config = SdkConfig()
        config.autoTrackDeviceAttributes = true
        sdkConfigStoreMock.config = config
        #if canImport(UIKit)
        messagingPush.deviceAttributes(deviceToken: givenDeviceToken) { defaultAttributes in
            let expectedAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            let expectedOS = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
            let expectedLocale = DeviceInfo.deviceLocale.value.replacingOccurrences(of: "_", with: "-")
            let expectedModel = UIDevice.deviceModelCode
            let expectedSDKVersion = SdkVersion.version
            XCTAssertEqual(defaultAttributes!["appVersion"], expectedAppVersion)
            XCTAssertEqual(defaultAttributes!["deviceOs"], expectedOS)
            XCTAssertEqual(defaultAttributes!["deviceLocale"], expectedLocale)
            XCTAssertEqual(defaultAttributes!["deviceModel"], expectedModel)
            XCTAssertEqual(defaultAttributes!["pushSubscribed"], "false")
            XCTAssertEqual(defaultAttributes!["cioSdkVersion"], expectedSDKVersion)
        }
        #endif
    }
    
    func test_deviceAttributes_givenDeviceToken_expectNil() {
        let givenDeviceToken = String.random
        var config = SdkConfig()
        config.autoTrackDeviceAttributes = false
        sdkConfigStoreMock.config = config

        // This function returns `nil` in case
        // `autoTrackDeviceAttributes` is set to `false`
        messagingPush.deviceAttributes(deviceToken: givenDeviceToken) { defaultAttributes in
            
            XCTAssertNil(defaultAttributes)
        }
    }
}
