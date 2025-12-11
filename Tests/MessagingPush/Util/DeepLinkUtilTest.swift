@_spi(Internal) @testable import CioInternalCommon
@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

class DeepLinkUtilTest: UnitTest {
    private var deepLinkUtil: DeepLinkUtilImpl!

    private let uiKitMock = UIKitWrapperMock()
    private var outputter = AccumulatorLogOutputter()

    override func setUp() {
        super.setUp()
        
        let logger = StandardLogger(logLevel: .debug, outputter: outputter)
        

        deepLinkUtil = DeepLinkUtilImpl(logger: logger, uiKitWrapper: uiKitMock)
    }

    // MARK: handleDeepLink

    func test_handleDeepLink_givenHostAppDoesNotHandleLink_expectOpenLinkSystemCall() {
        uiKitMock.continueNSUserActivityReturnValue = false

        deepLinkUtil.handleDeepLink(URL(string: "https://customer.io")!)

        XCTAssertEqual(uiKitMock.continueNSUserActivityCallsCount, 1)
        XCTAssertEqual(uiKitMock.openCallsCount, 1)
    }

    func test_handleDeepLink_givenHostAppDoesNotHandleLink_expectLogDeepLinkHandledExternally() {
        outputter.clear()
        let url = URL(string: "https://customer.io")!
        uiKitMock.continueNSUserActivityReturnValue = false

        deepLinkUtil.handleDeepLink(url)

        XCTAssertEqual(outputter.debugMessages.count, 2)
        XCTAssertEqual(outputter.firstDebugMessage, "[\(Tags.Push)] Handling push notification deep link with url: \(url)")
        XCTAssertEqual(outputter.debugMessages[1], "[\(Tags.Push)] Deep link handled by system")

//        XCTAssertEqual(loggerMock.logHandlingNotificationDeepLinkCallsCount, 1)
//        XCTAssertEqual(loggerMock.logHandlingNotificationDeepLinkReceivedArguments, url)
//
//        XCTAssertEqual(loggerMock.logDeepLinkHandledExternallyCallsCount, 1)
    }

    func test_handleDeepLink_givenHostAppHandlesLink_expectDoNotOpenLinkSystemCall() {
        uiKitMock.continueNSUserActivityReturnValue = true

        deepLinkUtil.handleDeepLink(URL(string: "https://customer.io")!)

        XCTAssertEqual(uiKitMock.continueNSUserActivityCallsCount, 1)
        XCTAssertFalse(uiKitMock.openCalled)
    }

    func test_handleDeepLink_givenHostAppHandlesLink_expectLogHandledByHostApp() {
        outputter.clear()
        let url = URL(string: "https://customer.io")!
        uiKitMock.continueNSUserActivityReturnValue = true

        deepLinkUtil.handleDeepLink(url)

        XCTAssertEqual(outputter.debugMessages.count, 2)
        XCTAssertEqual(outputter.firstDebugMessage, "[\(Tags.Push)] Handling push notification deep link with url: \(url)")
        XCTAssertEqual(outputter.debugMessages[1], "[\(Tags.Push)] Deep link handled by internal host app navigation")

//        XCTAssertEqual(loggerMock.logHandlingNotificationDeepLinkCallsCount, 1)
//        XCTAssertEqual(loggerMock.logHandlingNotificationDeepLinkReceivedArguments, url)
//
//        XCTAssertEqual(loggerMock.logDeepLinkHandledByHostAppCallsCount, 1)
    }

    func testHandleDeepLink_whenDLCallbackIsRegistered_expectDLCallbackToBeCalled() async {
        // Setup
        let callbackExpectation = XCTestExpectation(description: "callback expectation")
        let deepLinkCallback: DeepLinkCallback = { _ in
            callbackExpectation.fulfill()
            return true
        }
        deepLinkUtil.setDeepLinkCallback(deepLinkCallback)

        // Execution
        deepLinkUtil.handleDeepLink(URL(string: "https://customer.io")!)

        // Verification
        await fulfillment(of: [callbackExpectation], timeout: 1.0)
    }

    func testHandleDeepLink_whenDLCallbackIsRegistered_expectLogHandledByCallback() async {
        // Setup
        let url = URL(string: "https://customer.io")!
        let callbackExpectation = XCTestExpectation(description: "callback expectation")
        let deepLinkCallback: DeepLinkCallback = { _ in
            callbackExpectation.fulfill()
            return true
        }
        outputter.clear()
        deepLinkUtil.setDeepLinkCallback(deepLinkCallback)

        // Execution
        deepLinkUtil.handleDeepLink(url)

        // Verification
        await fulfillment(of: [callbackExpectation], timeout: 1.0)
        XCTAssertEqual(outputter.debugMessages.count, 2)
        XCTAssertEqual(outputter.firstDebugMessage, "[\(Tags.Push)] Handling push notification deep link with url: \(url)")
        XCTAssertEqual(outputter.debugMessages[1], "[\(Tags.Push)] Deep link handled by host app callback implementation")

//        XCTAssertEqual(loggerMock.logHandlingNotificationDeepLinkCallsCount, 1)
//        XCTAssertEqual(loggerMock.logHandlingNotificationDeepLinkReceivedArguments, url)
//
//        XCTAssertEqual(loggerMock.logDeepLinkHandledByCallbackCallsCount, 1)
    }
}
