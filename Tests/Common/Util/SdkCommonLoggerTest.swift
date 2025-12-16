@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class SdkCommonLoggerTest: UnitTest {

    func testCommonLoggerInitMessageAppears() {
        let outputter = AccumulatorLogDestination()
        let logger = StandardLogger(logLevel: .debug, destination: outputter)
        let version = SdkVersion.version

        logger.coreSdkInitStart()

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let firstMessage = outputter.firstDebugMessage!
        XCTAssertEqual(firstMessage.tag, Tags.Init)
        XCTAssertEqual(firstMessage.content, "Creating new instance of CustomerIO SDK version: \(version)...")
    }

    func testCommonLoggerInitCompleteMessageAppears() {
        let outputter = AccumulatorLogDestination()
        let logger = StandardLogger(logLevel: .debug, destination: outputter)

        logger.coreSdkInitSuccess()

        XCTAssertEqual(outputter.infoMessages.count, 1)
        let firstMessage = outputter.firstInfoMessage!
        XCTAssertEqual(firstMessage.tag, Tags.Init)
        XCTAssertEqual(firstMessage.content, "CustomerIO SDK is initialized and ready to use")
    }

    func testCommonLoggerModuleInitMessageAppears() {
        let outputter = AccumulatorLogDestination()
        let logger = StandardLogger(logLevel: .debug, destination: outputter)

        logger.moduleInitStart("MyModule")

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let firstMessage = outputter.firstDebugMessage!
        XCTAssertEqual(firstMessage.tag, Tags.Init)
        XCTAssertEqual(firstMessage.content, "Initializing SDK module MyModule...")
    }

    func testCommonLoggerModuleInitCompleteMessageAppears() {
        let outputter = AccumulatorLogDestination()
        let logger = StandardLogger(logLevel: .debug, destination: outputter)

        logger.moduleInitSuccess("PushModule")

        XCTAssertEqual(outputter.infoMessages.count, 1)
        let firstMessage = outputter.firstInfoMessage!
        XCTAssertEqual(firstMessage.tag, Tags.Init)
        XCTAssertEqual(firstMessage.content, "CustomerIO PushModule module is initialized and ready to use")
    }

    func testCommonLoggerDeepLinkMessageAppears() {
        let outputter = AccumulatorLogDestination()
        let logger = StandardLogger(logLevel: .debug, destination: outputter)
        let url = URL(string: "https://example.com/deeplink")!

        logger.logHandlingNotificationDeepLink(url: url)

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let firstMessage = outputter.firstDebugMessage!
        XCTAssertEqual(firstMessage.tag, Tags.Push)
        XCTAssertEqual(firstMessage.content, "Handling push notification deep link with url: \(url)")
    }

    func testCommonLoggerDeepLinkHandledByCallbackMessageAppears() {
        let outputter = AccumulatorLogDestination()
        let logger = StandardLogger(logLevel: .debug, destination: outputter)

        logger.logDeepLinkHandledByCallback()

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let firstMessage = outputter.firstDebugMessage!
        XCTAssertEqual(firstMessage.tag, Tags.Push)
        XCTAssertEqual(firstMessage.content, "Deep link handled by host app callback implementation")
    }

    func testCommonLoggerDeepLinkHandledByHostMessageAppears() {
        let outputter = AccumulatorLogDestination()
        let logger = StandardLogger(logLevel: .debug, destination: outputter)

        logger.logDeepLinkHandledByHostApp()

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let firstMessage = outputter.firstDebugMessage!
        XCTAssertEqual(firstMessage.tag, Tags.Push)
        XCTAssertEqual(firstMessage.content, "Deep link handled by internal host app navigation")
    }

    func testCommonLoggerDeepLinkHandledExternallyMessageAppears() {
        let outputter = AccumulatorLogDestination()
        let logger = StandardLogger(logLevel: .debug, destination: outputter)

        logger.logDeepLinkHandledExternally()

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let firstMessage = outputter.firstDebugMessage!
        XCTAssertEqual(firstMessage.tag, Tags.Push)
        XCTAssertEqual(firstMessage.content, "Deep link handled by system")
    }

    func testCommonLoggerDeepLinkNotHandledMessageAppears() {
        let outputter = AccumulatorLogDestination()
        let logger = StandardLogger(logLevel: .debug, destination: outputter)

        logger.logDeepLinkWasNotHandled()

        XCTAssertEqual(outputter.debugMessages.count, 1)
        let firstMessage = outputter.firstDebugMessage!
        XCTAssertEqual(firstMessage.tag, Tags.Push)
        XCTAssertEqual(firstMessage.content, "Deep link was not handled")
    }
}
