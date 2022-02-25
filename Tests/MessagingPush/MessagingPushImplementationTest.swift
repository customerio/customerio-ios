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
        messagingPush = MessagingPushImplementation(siteId: testSiteId, profileStore: profileStoreMock,
                                                    backgroundQueue: queueMock,
                                                    globalDataStore: globalDataStoreMock, logger: log,
                                                    sdkConfigStore: sdkConfigStoreMock, jsonAdapter: jsonAdapter)
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

        configureDeviceAttributes(to: true)
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
    func test_deviceAttributes_givenDefaultDeviceAttributesEnabled_expectGetDefaultDeviceMetrics() {
        configureDeviceAttributes(to: true)
        #if canImport(UIKit)
        messagingPush.getDefaultDeviceAttributes{ defaultAttributes in
            let expectedAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            let expectedOS = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
            let expectedLocale = DeviceInfo().deviceLocale.replacingOccurrences(of: "_", with: "-")
            let expectedModel = UIDevice.deviceModelCode
            let expectedSDKVersion = SdkVersion.version
            XCTAssertEqual(defaultAttributes!["app_version"], expectedAppVersion)
            XCTAssertEqual(defaultAttributes!["device_os"], expectedOS)
            XCTAssertEqual(defaultAttributes!["device_locale"], expectedLocale)
            XCTAssertEqual(defaultAttributes!["device_model"], expectedModel)
            XCTAssertEqual(defaultAttributes!["push_subscribed"], "false")
            XCTAssertEqual(defaultAttributes!["cio_sdk_version"], expectedSDKVersion)
        }
        #endif
    }
    
    func test_deviceAttributes_givenDefaultDeviceAttributesDisabled_expectNil() {
        let givenDeviceToken = String.random
        configureDeviceAttributes(to: false)

        // This function returns `nil` in case
        // `autoTrackDeviceAttributes` is set to `false`
        messagingPush.getDefaultDeviceAttributes{ defaultAttributes in
            
            XCTAssertNil(defaultAttributes)
        }
    }
    
    private func configureDeviceAttributes(to value : Bool) {
        var config = SdkConfig()
        config.autoTrackDeviceAttributes = value
        sdkConfigStoreMock.config = config
    }
}
