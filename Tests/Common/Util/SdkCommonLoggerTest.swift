@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class SdkCommonLoggerTest: UnitTest {

    func testCommonLoggerInitMessageAppears() {
        let outputter = AccumulatorLogOutputter()
        let logger = StandardLogger(logLevel: .debug, outputter: outputter)
        let version = SdkVersion.version

        logger.coreSdkInitStart()

        XCTAssertEqual(outputter.debugMessages.count, 1)
        XCTAssertEqual(
            outputter.firstDebugMessage,
            "[\(Tags.Init)] Creating new instance of CustomerIO SDK version: \(version)..."
        )
    }

    func testCommonLoggerInitCompleteMessageAppears() {
        let outputter = AccumulatorLogOutputter()
        let logger = StandardLogger(logLevel: .debug, outputter: outputter)

        logger.coreSdkInitSuccess()

        XCTAssertEqual(outputter.infoMessages.count, 1)
        XCTAssertEqual(
            outputter.firstInfoMessage,
            "[\(Tags.Init)] CustomerIO SDK is initialized and ready to use"
        )
    }

    func testCommonLoggerModuleInitMessageAppears() {
        let outputter = AccumulatorLogOutputter()
        let logger = StandardLogger(logLevel: .debug, outputter: outputter)

        logger.moduleInitStart("MyModule")

        XCTAssertEqual(outputter.debugMessages.count, 1)
        XCTAssertEqual(
            outputter.firstDebugMessage,
            "[\(Tags.Init)] Initializing SDK module MyModule..."
        )
    }

    func testCommonLoggerModuleInitCompleteMessageAppears() {
        let outputter = AccumulatorLogOutputter()
        let logger = StandardLogger(logLevel: .debug, outputter: outputter)

        logger.moduleInitSuccess("PushModule")

        XCTAssertEqual(outputter.infoMessages.count, 1)
        XCTAssertEqual(
            outputter.firstInfoMessage,
            "[\(Tags.Init)] CustomerIO PushModule module is initialized and ready to use"
        )
    }

    func testCommonLoggerDeepLinkMessageAppears() {
        let outputter = AccumulatorLogOutputter()
        let logger = StandardLogger(logLevel: .debug, outputter: outputter)
        let url = URL(string: "https://example.com/deeplink")!

        logger.logHandlingNotificationDeepLink(url: url)

        XCTAssertEqual(outputter.debugMessages.count, 1)
        XCTAssertEqual(
            outputter.firstDebugMessage,
            "[\(Tags.Push)] Handling push notification deep link with url: \(url)"
        )
    }

    func testCommonLoggerDeepLinkHandledByCallbackMessageAppears() {
        let outputter = AccumulatorLogOutputter()
        let logger = StandardLogger(logLevel: .debug, outputter: outputter)

        logger.logDeepLinkHandledByCallback()

        XCTAssertEqual(outputter.debugMessages.count, 1)
        XCTAssertEqual(
            outputter.firstDebugMessage,
            "[\(Tags.Push)] Deep link handled by host app callback implementation"
        )
    }

    func testCommonLoggerDeepLinkHandledByHostMessageAppears() {
        let outputter = AccumulatorLogOutputter()
        let logger = StandardLogger(logLevel: .debug, outputter: outputter)

        logger.logDeepLinkHandledByHostApp()

        XCTAssertEqual(outputter.debugMessages.count, 1)
        XCTAssertEqual(
            outputter.firstDebugMessage,
            "[\(Tags.Push)] Deep link handled by internal host app navigation"
        )
    }

    func testCommonLoggerDeepLinkHandledExternallyMessageAppears() {
        let outputter = AccumulatorLogOutputter()
        let logger = StandardLogger(logLevel: .debug, outputter: outputter)

        logger.logDeepLinkHandledExternally()

        XCTAssertEqual(outputter.debugMessages.count, 1)
        XCTAssertEqual(
            outputter.firstDebugMessage,
            "[\(Tags.Push)] Deep link handled by system"
        )
    }

    func testCommonLoggerDeepLinkNotHandledMessageAppears() {
        let outputter = AccumulatorLogOutputter()
        let logger = StandardLogger(logLevel: .debug, outputter: outputter)

        logger.logDeepLinkWasNotHandled()

        XCTAssertEqual(outputter.debugMessages.count, 1)
        XCTAssertEqual(
            outputter.firstDebugMessage,
            "[\(Tags.Push)] Deep link was not handled"
        )
    }
}
