@_spi(Internal) @testable import CioInternalCommon
@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

class DeepLinkUtilTest: UnitTest {
    private var deepLinkUtil: DeepLinkUtilImpl!

    private let uiKitMock = UIKitWrapperMock()

    override func setUp() {
        super.setUp()

        deepLinkUtil = DeepLinkUtilImpl(logger: log, uiKitWrapper: uiKitMock)
    }

    // MARK: handleDeepLink

    func test_handleDeepLink_givenHostAppDoesNotHandleLink_expectOpenLinkSystemCall() {
        uiKitMock.continueNSUserActivityReturnValue = false

        deepLinkUtil.handleDeepLink(URL(string: "https://customer.io")!)

        XCTAssertEqual(uiKitMock.continueNSUserActivityCallsCount, 1)
        XCTAssertEqual(uiKitMock.openCallsCount, 1)
    }

    func test_handleDeepLink_givenHostAppHandlesLink_expectDoNotOpenLinkSystemCall() {
        uiKitMock.continueNSUserActivityReturnValue = true

        deepLinkUtil.handleDeepLink(URL(string: "https://customer.io")!)

        XCTAssertEqual(uiKitMock.continueNSUserActivityCallsCount, 1)
        XCTAssertFalse(uiKitMock.openCalled)
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
}
