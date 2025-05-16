@_spi(Internal) @testable import CioInternalCommon
@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

class DeepLinkUtilTest: UnitTest {
    private var deepLinkUtil: DeepLinkUtilImpl!

    private let uiKitMock = UIKitWrapperMock()
    private let loggerMock = SdkCommonLoggerMock()

    override func setUp() {
        super.setUp()

        deepLinkUtil = DeepLinkUtilImpl(logger: loggerMock, uiKitWrapper: uiKitMock)
    }

    // MARK: handleDeepLink

    func test_handleDeepLink_givenHostAppDoesNotHandleLink_expectOpenLinkSystemCall() {
        uiKitMock.continueNSUserActivityReturnValue = false

        deepLinkUtil.handleDeepLink(URL(string: "https://customer.io")!)

        XCTAssertEqual(uiKitMock.continueNSUserActivityCallsCount, 1)
        XCTAssertEqual(uiKitMock.openCallsCount, 1)
    }

    func test_handleDeepLink_givenHostAppDoesNotHandleLink_expectLogDeepLinkHandledExternally() {
        let url = URL(string: "https://customer.io")!
        uiKitMock.continueNSUserActivityReturnValue = false

        deepLinkUtil.handleDeepLink(url)

        XCTAssertEqual(loggerMock.logHandlingNotificationDeepLinkCallsCount, 1)
        XCTAssertEqual(loggerMock.logHandlingNotificationDeepLinkReceivedArguments, url)

        XCTAssertEqual(loggerMock.logDeepLinkHandledExternallyCallsCount, 1)
    }

    func test_handleDeepLink_givenHostAppHandlesLink_expectDoNotOpenLinkSystemCall() {
        uiKitMock.continueNSUserActivityReturnValue = true

        deepLinkUtil.handleDeepLink(URL(string: "https://customer.io")!)

        XCTAssertEqual(uiKitMock.continueNSUserActivityCallsCount, 1)
        XCTAssertFalse(uiKitMock.openCalled)
    }

    func test_handleDeepLink_givenHostAppHandlesLink_expectLogHandledByHostApp() {
        let url = URL(string: "https://customer.io")!
        uiKitMock.continueNSUserActivityReturnValue = true

        deepLinkUtil.handleDeepLink(url)

        XCTAssertEqual(loggerMock.logHandlingNotificationDeepLinkCallsCount, 1)
        XCTAssertEqual(loggerMock.logHandlingNotificationDeepLinkReceivedArguments, url)

        XCTAssertEqual(loggerMock.logDeepLinkHandledByHostAppCallsCount, 1)
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
        deepLinkUtil.setDeepLinkCallback(deepLinkCallback)

        // Execution
        deepLinkUtil.handleDeepLink(url)

        // Verification
        await fulfillment(of: [callbackExpectation], timeout: 1.0)
        XCTAssertEqual(loggerMock.logHandlingNotificationDeepLinkCallsCount, 1)
        XCTAssertEqual(loggerMock.logHandlingNotificationDeepLinkReceivedArguments, url)

        XCTAssertEqual(loggerMock.logDeepLinkHandledByCallbackCallsCount, 1)
    }
}
