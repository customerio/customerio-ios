@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class DataPipelinesLoggerTests: UnitTest {
    private let loggerMock = LoggerMock()
    var logger: DataPipelinesLogger!

    override func setUp() {
        super.setUp()

        logger = DataPipelinesLoggerImpl(logger: loggerMock)
    }

    func test_logStoringDevicePushToken_logsExpectedMessage() {
        let token = "token"
        let userId = "user-id"

        logger.logStoringDevicePushToken(token: token, userId: userId)

        XCTAssertEqual(loggerMock.debugReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.debugReceivedInvocations.first?.tag, "Push")
        XCTAssertEqual(
            loggerMock.debugReceivedInvocations.first?.message,
            "Storing device token: token for user profile: user-id"
        )
    }

    func test_logStoringBlankPushToken_logsExpectedMessage() {
        logger.logStoringBlankPushToken()

        XCTAssertEqual(loggerMock.debugReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.debugReceivedInvocations.first?.tag, "Push")
        XCTAssertEqual(
            loggerMock.debugReceivedInvocations.first?.message,
            "Attempting to register blank token, ignoring request"
        )
    }

    func test_logRegisteringPushToken_logsExpectedMessage() {
        let token = "token"
        let userId = "user-id"

        logger.logRegisteringPushToken(token: token, userId: userId)

        XCTAssertEqual(loggerMock.debugReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.debugReceivedInvocations.first?.tag, "Push")
        XCTAssertEqual(
            loggerMock.debugReceivedInvocations.first?.message,
            "Registering device token: token for user profile: user-id"
        )
    }

    func test_logPushTokenRefreshed_logsExpectedMessage() {
        logger.logPushTokenRefreshed()

        XCTAssertEqual(loggerMock.debugReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.debugReceivedInvocations.first?.tag, "Push")
        XCTAssertEqual(
            loggerMock.debugReceivedInvocations.first?.message,
            "Token refreshed, deleting old token to avoid registering same device multiple times"
        )
    }
}
