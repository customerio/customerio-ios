@testable import CioInternalCommon
@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

class PushNotificationLoggerTests: UnitTest {
    
    let outputter = AccumulatorLogDestination()
    var logger: PushNotificationLogger!

    override func setUp() {
        super.setUp()

        logger = PushNotificationLoggerImpl(logger: StandardLogger(logLevel: .debug, destination: outputter))
    }

    func test_logReceivedPushMessage_logsExpectedMessage() {
        let notification = PushNotificationStub.getPushSentFromCIO()

        logger.logReceivedPushMessage(notification: notification)

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let first = outputter.firstDebugMessage!
        XCTAssertEqual(first.tag, Tags.Push)
        XCTAssertEqual(
            first.content,
            "Received notification for message: \(notification)"
        )
    }

    func test_logReceivedCioPushMessage_logsExpectedMessage() {
        logger.logReceivedCioPushMessage()

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let first = outputter.firstDebugMessage!
        XCTAssertEqual(first.tag, Tags.Push)
        XCTAssertEqual(
            first.content,
            "Received CIO push message"
        )
    }

    func test_logReceivedNonCioPushMessage_logsExpectedMessage() {
        logger.logReceivedNonCioPushMessage()

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let first = outputter.firstDebugMessage!
        XCTAssertEqual(first.tag, Tags.Push)
        XCTAssertEqual(
            first.content,
            "Received non CIO push message, ignoring message"
        )
    }

    func test_logReceivedPushMessageWithEmptyDeliveryId_logsExpectedMessage() {
        logger.logReceivedPushMessageWithEmptyDeliveryId()

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let first = outputter.firstDebugMessage!
        XCTAssertEqual(first.tag, Tags.Push)
        XCTAssertEqual(
            first.content,
            "Received message with empty deliveryId"
        )
    }

    func test_logTrackingPushMessageDelivered_logsExpectedMessage() {
        let deliveryId = "abc123"

        logger.logTrackingPushMessageDelivered(deliveryId: deliveryId)

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let first = outputter.firstDebugMessage!
        XCTAssertEqual(first.tag, Tags.Push)
        XCTAssertEqual(
            first.content,
            "Tracking push message delivered with deliveryId: \(deliveryId)"
        )
    }

    func test_logPushMetricsAutoTrackingDisabled_logsExpectedMessage() {
        logger.logPushMetricsAutoTrackingDisabled()

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let first = outputter.firstDebugMessage!
        XCTAssertEqual(first.tag, Tags.Push)
        XCTAssertEqual(
            first.content,
            "Received message but auto tracking is disabled"
        )
    }

    func test_logPushMetricTracked_logsExpectedMessage() {
        let deliveryId = "abc123"
        let event = "delivered"

        logger.logPushMetricTracked(deliveryId: deliveryId, event: event)

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let first = outputter.firstDebugMessage!
        XCTAssertEqual(first.tag, Tags.Push)
        XCTAssertEqual(
            first.content,
            "Successfully tracked push metric '\(event)' for deliveryId: \(deliveryId)"
        )
    }

    func test_logPushMetricTrackingFailed_logsExpectedMessage() {
        let deliveryId = "abc123"
        let event = "delivered"
        let error = NSError(domain: "TestError", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test error"])

        logger.logPushMetricTrackingFailed(deliveryId: deliveryId, event: event, error: error)

        XCTAssertEqual(outputter.errorMessages.count, 1)
        let first = outputter.firstErrorMessage!
        XCTAssertEqual(first.tag, Tags.Push)
        XCTAssertEqual(
            first.content,
            "Failed to track push metric '\(event)' for deliveryId: \(deliveryId) Error: \(error.localizedDescription)"
        )
    }

    func test_logClickedPushMessage_logsExpectedMessage() {
        let notification = PushNotificationStub.getPushSentFromCIO()

        logger.logClickedPushMessage(notification: notification)

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let first = outputter.firstDebugMessage!
        XCTAssertEqual(first.tag, Tags.Push)
        XCTAssertEqual(
            first.content,
            "Clicked notification for message: \(notification)"
        )
    }

    func test_logClickedCioPushMessage_logsExpectedMessage() {
        logger.logClickedCioPushMessage()

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let first = outputter.firstDebugMessage!
        XCTAssertEqual(first.tag, Tags.Push)
        XCTAssertEqual(
            first.content,
            "Clicked CIO push message"
        )
    }

    func test_logClickedNonCioPushMessage_logsExpectedMessage() {
        logger.logClickedNonCioPushMessage()

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let first = outputter.firstDebugMessage!
        XCTAssertEqual(first.tag, Tags.Push)
        XCTAssertEqual(
            first.content,
            "Clicked non CIO push message, ignoring message"
        )
    }

    func test_logClickedPushMessageWithEmptyDeliveryId_logsExpectedMessage() {
        logger.logClickedPushMessageWithEmptyDeliveryId()

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let first = outputter.firstDebugMessage!
        XCTAssertEqual(first.tag, Tags.Push)
        XCTAssertEqual(
            first.content,
            "Clicked message with empty deliveryId"
        )
    }

    func test_logTrackingPushMessageOpened_logsExpectedMessage() {
        let deliveryId = "xyz456"

        logger.logTrackingPushMessageOpened(deliveryId: deliveryId)

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let first = outputter.firstDebugMessage!
        XCTAssertEqual(first.tag, Tags.Push)
        XCTAssertEqual(
            first.content,
            "Tracking push message opened with deliveryId: \(deliveryId)"
        )
    }
}
