@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class SdkCommonLoggerTest: UnitTest {
    private let loggerMock = LoggerMock()
    var logger: SdkCommonLogger!

    override func setUp() {
        super.setUp()

        logger = SdkCommonLoggerImpl(logger: loggerMock)
    }

    override func tearDown() {
        logger = nil
        super.tearDown()
    }

    func test_coreSdkInitStart_logsExpectedMessage() {
        let version = SdkVersion.version
        logger.coreSdkInitStart()

        XCTAssertEqual(loggerMock.debugReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.debugReceivedInvocations.first?.tag, "Init")
        XCTAssertEqual(
            loggerMock.debugReceivedInvocations.first?.message,
            "Creating new instance of CustomerIO SDK version: \(version)..."
        )
    }

    func test_coreSdkInitSuccess_logsExpectedMessage() {
        logger.coreSdkInitSuccess()

        XCTAssertEqual(loggerMock.infoReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.infoReceivedInvocations.first?.tag, "Init")
        XCTAssertEqual(
            loggerMock.infoReceivedInvocations.first?.message,
            "CustomerIO SDK is initialized and ready to use"
        )
    }

    func test_moduleInitStart_logsWithModuleName() {
        logger.moduleInitStart("MyModule")

        XCTAssertEqual(loggerMock.debugReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.debugReceivedInvocations.first?.tag, "Init")
        XCTAssertEqual(
            loggerMock.debugReceivedInvocations.first?.message,
            "Initializing SDK module MyModule..."
        )
    }

    func test_moduleInitSuccess_logsWithModuleName() {
        logger.moduleInitSuccess("PushModule")

        XCTAssertEqual(loggerMock.infoReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.infoReceivedInvocations.first?.tag, "Init")
        XCTAssertEqual(
            loggerMock.infoReceivedInvocations.first?.message,
            "CustomerIO PushModule module is initialized and ready to use"
        )
    }

    func test_logHandlingNotificationDeepLink_logsExpectedMessage() {
        let url = URL(string: "https://example.com/deeplink")!

        logger.logHandlingNotificationDeepLink(url: url)

        XCTAssertEqual(loggerMock.debugReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.debugReceivedInvocations.first?.tag, "Push")
        XCTAssertEqual(
            loggerMock.debugReceivedInvocations.first?.message,
            "Handling push notification deep link with url: \(url)"
        )
    }

    func test_logDeepLinkHandledByCallback_logsExpectedMessage() {
        logger.logDeepLinkHandledByCallback()

        XCTAssertEqual(loggerMock.debugReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.debugReceivedInvocations.first?.tag, "Push")
        XCTAssertEqual(
            loggerMock.debugReceivedInvocations.first?.message,
            "Deep link handled by host app callback implementation"
        )
    }

    func test_logDeepLinkHandledByHostApp_logsExpectedMessage() {
        logger.logDeepLinkHandledByHostApp()

        XCTAssertEqual(loggerMock.debugReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.debugReceivedInvocations.first?.tag, "Push")
        XCTAssertEqual(
            loggerMock.debugReceivedInvocations.first?.message,
            "Deep link handled by internal host app navigation"
        )
    }

    func test_logDeepLinkHandledExternally_logsExpectedMessage() {
        logger.logDeepLinkHandledExternally()

        XCTAssertEqual(loggerMock.debugReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.debugReceivedInvocations.first?.tag, "Push")
        XCTAssertEqual(
            loggerMock.debugReceivedInvocations.first?.message,
            "Deep link handled by system"
        )
    }

    func test_logDeepLinkWasNotHandled_logsExpectedMessage() {
        logger.logDeepLinkWasNotHandled()

        XCTAssertEqual(loggerMock.debugReceivedInvocations.count, 1)
        XCTAssertEqual(loggerMock.debugReceivedInvocations.first?.tag, "Push")
        XCTAssertEqual(
            loggerMock.debugReceivedInvocations.first?.message,
            "Deep link was not handled"
        )
    }
}
