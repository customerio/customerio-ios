@testable import CioInternalCommon
@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

class PushNotificationLoggerTests: UnitTest {
    private let loggerMock = LoggerMock()
    var logger: PushNotificationLogger!

    override func setUp() {
        super.setUp()

        logger = PushNotificationLoggerImpl(logger: loggerMock)
    }

    func test_logReceivedPushMessage_logsExpectedMessage() {
        let notification = PushNotificationStub.getPushSentFromCIO()

        logger.logReceivedPushMessage(notification: notification)

        XCTAssertEqual(loggerMock.debugReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.debugReceivedInvocations.first?.tag, "Push")
        XCTAssertEqual(
            loggerMock.debugReceivedInvocations.first?.message, "Received notification for message: \(notification)"
        )
    }

    func test_logReceivedCioPushMessage_logsExpectedMessage() {
        logger.logReceivedCioPushMessage()

        XCTAssertEqual(loggerMock.debugReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.debugReceivedInvocations.first?.tag, "Push")
        XCTAssertEqual(
            loggerMock.debugReceivedInvocations.first?.message,
            "Received CIO push message"
        )
    }

    func test_logReceivedNonCioPushMessage_logsExpectedMessage() {
        logger.logReceivedNonCioPushMessage()

        XCTAssertEqual(loggerMock.debugReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.debugReceivedInvocations.first?.tag, "Push")
        XCTAssertEqual(
            loggerMock.debugReceivedInvocations.first?.message,
            "Received non CIO push message, ignoring message"
        )
    }

    func test_logReceivedPushMessageWithEmptyDeliveryId_logsExpectedMessage() {
        logger.logReceivedPushMessageWithEmptyDeliveryId()

        XCTAssertEqual(loggerMock.debugReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.debugReceivedInvocations.first?.tag, "Push")
        XCTAssertEqual(
            loggerMock.debugReceivedInvocations.first?.message,
            "Received message with empty deliveryId"
        )
    }

    func test_logTrackingPushMessageDelivered_logsExpectedMessage() {
        let deliveryId = "abc123"

        logger.logTrackingPushMessageDelivered(deliveryId: deliveryId)

        XCTAssertEqual(loggerMock.debugReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.debugReceivedInvocations.first?.tag, "Push")
        XCTAssertEqual(
            loggerMock.debugReceivedInvocations.first?.message,
            "Tracking push message delivered with deliveryId: \(deliveryId)"
        )
    }

    func test_logPushMetricsAutoTrackingDisabled_logsExpectedMessage() {
        logger.logPushMetricsAutoTrackingDisabled()

        XCTAssertEqual(loggerMock.debugReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.debugReceivedInvocations.first?.tag, "Push")
        XCTAssertEqual(
            loggerMock.debugReceivedInvocations.first?.message,
            "Received message but auto tracking is disabled"
        )
    }

    func test_logClickedPushMessage_logsExpectedMessage() {
        let notification = PushNotificationStub.getPushSentFromCIO()

        logger.logClickedPushMessage(notification: notification)

        XCTAssertEqual(loggerMock.debugReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.debugReceivedInvocations.first?.tag, "Push")
        XCTAssertEqual(
            loggerMock.debugReceivedInvocations.first?.message,
            "Clicked notification for message: \(notification)"
        )
    }

    func test_logClickedCioPushMessage_logsExpectedMessage() {
        logger.logClickedCioPushMessage()

        XCTAssertEqual(loggerMock.debugReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.debugReceivedInvocations.first?.tag, "Push")
        XCTAssertEqual(
            loggerMock.debugReceivedInvocations.first?.message,
            "Clicked CIO push message"
        )
    }

    func test_logClickedNonCioPushMessage_logsExpectedMessage() {
        logger.logClickedNonCioPushMessage()

        XCTAssertEqual(loggerMock.debugReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.debugReceivedInvocations.first?.tag, "Push")
        XCTAssertEqual(
            loggerMock.debugReceivedInvocations.first?.message,
            "Clicked non CIO push message, ignoring message"
        )
    }

    func test_logClickedPushMessageWithEmptyDeliveryId_logsExpectedMessage() {
        logger.logClickedPushMessageWithEmptyDeliveryId()

        XCTAssertEqual(loggerMock.debugReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.debugReceivedInvocations.first?.tag, "Push")
        XCTAssertEqual(
            loggerMock.debugReceivedInvocations.first?.message,
            "Clicked message with empty deliveryId"
        )
    }

    func test_logTrackingPushMessageOpened_logsExpectedMessage() {
        let deliveryId = "xyz456"

        logger.logTrackingPushMessageOpened(deliveryId: deliveryId)

        XCTAssertEqual(loggerMock.debugReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.debugReceivedInvocations.first?.tag, "Push")
        XCTAssertEqual(
            loggerMock.debugReceivedInvocations.first?.message,
            "Tracking push message opened with deliveryId: \(deliveryId)"
        )
    }
}
