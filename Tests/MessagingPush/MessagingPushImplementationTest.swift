@testable import CioInternalCommon
@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

class MessagingPushImplementationTest: UnitTest {
    private var pushLoggerMock: PushNotificationLoggerMock!
    private var richPushDeliveryTrackerMock: RichPushDeliveryTrackerMock!
    private var implementation: MessagingPushImplementation!

    override func setUp() {
        super.setUp()

        pushLoggerMock = PushNotificationLoggerMock()
        richPushDeliveryTrackerMock = RichPushDeliveryTrackerMock()

        diGraphShared.override(value: pushLoggerMock, forType: PushNotificationLogger.self)
        diGraphShared.override(value: richPushDeliveryTrackerMock, forType: RichPushDeliveryTracker.self)

        implementation = MessagingPushImplementation(
            diGraph: diGraphShared,
            moduleConfig: MessagingPushConfigBuilder().build()
        )
    }

    // MARK: trackMetricFromNSE

    func test_trackMetricFromNSE_givenSuccess_expectLogSuccessMessage() {
        let deliveryId = "test-delivery-id"
        let event = Metric.delivered
        let deviceToken = "test-device-token"

        richPushDeliveryTrackerMock.trackMetricClosure = { _, _, _, _, completion in
            completion(.success(()))
        }

        implementation.trackMetricFromNSE(deliveryID: deliveryId, event: event, deviceToken: deviceToken)

        XCTAssertEqual(richPushDeliveryTrackerMock.trackMetricCallsCount, 1)
        XCTAssertEqual(richPushDeliveryTrackerMock.trackMetricReceivedInvocations.first?.token, deviceToken)
        XCTAssertEqual(richPushDeliveryTrackerMock.trackMetricReceivedInvocations.first?.event, event)
        XCTAssertEqual(richPushDeliveryTrackerMock.trackMetricReceivedInvocations.first?.deliveryId, deliveryId)
        XCTAssertNil(richPushDeliveryTrackerMock.trackMetricReceivedInvocations.first?.timestamp)

        XCTAssertEqual(pushLoggerMock.logPushMetricTrackedCallsCount, 1)
        XCTAssertEqual(pushLoggerMock.logPushMetricTrackedReceivedInvocations.first?.deliveryId, deliveryId)
        XCTAssertEqual(pushLoggerMock.logPushMetricTrackedReceivedInvocations.first?.event, event.rawValue)

        XCTAssertEqual(pushLoggerMock.logPushMetricTrackingFailedCallsCount, 0)
    }

    func test_trackMetricFromNSE_givenFailure_expectLogErrorMessage() {
        let deliveryId = "test-delivery-id"
        let event = Metric.delivered
        let deviceToken = "test-device-token"
        let testError = HttpRequestError.noRequestMade(nil)

        richPushDeliveryTrackerMock.trackMetricClosure = { _, _, _, _, completion in
            completion(.failure(testError))
        }

        implementation.trackMetricFromNSE(deliveryID: deliveryId, event: event, deviceToken: deviceToken)

        XCTAssertEqual(richPushDeliveryTrackerMock.trackMetricCallsCount, 1)
        XCTAssertEqual(richPushDeliveryTrackerMock.trackMetricReceivedInvocations.first?.token, deviceToken)
        XCTAssertEqual(richPushDeliveryTrackerMock.trackMetricReceivedInvocations.first?.event, event)
        XCTAssertEqual(richPushDeliveryTrackerMock.trackMetricReceivedInvocations.first?.deliveryId, deliveryId)
        XCTAssertNil(richPushDeliveryTrackerMock.trackMetricReceivedInvocations.first?.timestamp)

        XCTAssertEqual(pushLoggerMock.logPushMetricTrackingFailedCallsCount, 1)
        XCTAssertEqual(pushLoggerMock.logPushMetricTrackingFailedReceivedInvocations.first?.deliveryId, deliveryId)
        XCTAssertEqual(pushLoggerMock.logPushMetricTrackingFailedReceivedInvocations.first?.event, event.rawValue)

        XCTAssertEqual(pushLoggerMock.logPushMetricTrackedCallsCount, 0)
    }
}
