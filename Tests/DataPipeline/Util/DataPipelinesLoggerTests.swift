@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class DataPipelinesLoggerTests: UnitTest {
    let outputter = AccumulatorLogDestination()
    var logger: DataPipelinesLogger!

    override func setUp() {
        super.setUp()

        logger = DataPipelinesLoggerImpl(logger: StandardLogger(logLevel: .debug, destination: outputter))
    }

    func test_logStoringDevicePushToken_logsExpectedMessage() {
        let token = "token"
        let userId = "user-id"

        outputter.clear()
        logger.logStoringDevicePushToken(token: token, userId: userId)

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let first = outputter.firstDebugMessage!
        XCTAssertEqual(first.tag, Tags.Push)
        XCTAssertEqual(
            first.content,
            "Storing device token: \(token) for user profile: \(userId)"
        )
    }

    func test_logStoringBlankPushToken_logsExpectedMessage() {

        outputter.clear()
        logger.logStoringBlankPushToken()

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let first = outputter.firstDebugMessage!
        XCTAssertEqual(first.tag, Tags.Push)
        XCTAssertEqual(
            first.content,
            "Attempting to register blank token, ignoring request"
        )
    }

    func test_logRegisteringPushToken_logsExpectedMessage() {
        let token = "token"
        let userId = "user-id"

        outputter.clear()
        logger.logRegisteringPushToken(token: token, userId: userId)

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let first = outputter.firstDebugMessage!
        XCTAssertEqual(first.tag, Tags.Push)
        XCTAssertEqual(
            first.content,
            "Registering device token: \(token) for user profile: \(userId)"
        )
    }

    func test_logPushTokenRefreshed_logsExpectedMessage() {

        outputter.clear()
        logger.logPushTokenRefreshed()

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let first = outputter.firstDebugMessage!
        XCTAssertEqual(first.tag, Tags.Push)
        XCTAssertEqual(
            first.content,
            "Token refreshed, deleting old token to avoid registering same device multiple times"
        )
    }

    func test_automaticTokenRegistrationForNewProfile_logsExpectedMessage() {

        outputter.clear()
        logger.automaticTokenRegistrationForNewProfile(token: "token", userId: "userId")

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let first = outputter.firstDebugMessage!
        XCTAssertEqual(first.tag, Tags.Push)
        XCTAssertEqual(
            first.content,
            "Automatically registering device token: token to newly identified profile: userId"
        )
    }

    func test_logDeletingTokenDueToNewProfileIdentification_logsExpectedMessage() {

        outputter.clear()
        logger.logDeletingTokenDueToNewProfileIdentification()

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let first = outputter.firstDebugMessage!
        XCTAssertEqual(first.tag, Tags.Push)
        XCTAssertEqual(
            first.content,
            "Deleting device token before identifying new profile"
        )
    }

    func test_logTrackingDevicesAttributesWithoutValidToken_logsExpectedMessage() {

        outputter.clear()
        logger.logTrackingDevicesAttributesWithoutValidToken()

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let first = outputter.firstDebugMessage!
        XCTAssertEqual(first.tag, Tags.Push)
        XCTAssertEqual(
            first.content,
            "No device token found. ignoring request to track device attributes"
        )
    }
}
