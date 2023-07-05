@testable import CioInternalCommon
@testable import CioMessagingPush
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class DeepLinkUtilTest: UnitTest {
    private var deepLinkUtil: DeepLinkUtilImpl!

    private let uiKitMock = UIKitWrapperMock()
    private let deepLinkDelegateMock = DeepLinkDelegateMock()

    override func setUp() {
        super.setUp()

        deepLinkUtil = DeepLinkUtilImpl(logger: log, uiKitWrapper: uiKitMock)
    }

    // MARK: handleDeepLink

    func test_handleDeepLink_givenHostAppProvidesDelegate() {
        deepLinkDelegateMock.onOpenDeepLinkReturnValue = true

        deepLinkUtil.handleDeepLink(URL(string: "https://customer.io")!, deepLinkDelegate: deepLinkDelegateMock)

        XCTAssertEqual(deepLinkDelegateMock.onOpenDeepLinkCallsCount, 1)
        XCTAssertFalse(uiKitMock.continueNSUserActivityCalled)
        XCTAssertFalse(uiKitMock.openCalled)
    }

    func test_handleDeepLink_givenContinueNSUserActivityHandlesLink() {
        // Test when no delegate provided
        uiKitMock.continueNSUserActivityReturnValue = true

        deepLinkUtil.handleDeepLink(URL(string: "https://customer.io")!, deepLinkDelegate: nil)

        XCTAssertFalse(deepLinkDelegateMock.onOpenDeepLinkCalled)
        XCTAssertEqual(uiKitMock.continueNSUserActivityCallsCount, 1)
        XCTAssertFalse(uiKitMock.openCalled)

        // Same behavior expected when delegate returns false
        deepLinkDelegateMock.onOpenDeepLinkReturnValue = false

        deepLinkUtil.handleDeepLink(URL(string: "https://customer.io")!, deepLinkDelegate: deepLinkDelegateMock)

        XCTAssertEqual(deepLinkDelegateMock.onOpenDeepLinkCallsCount, 1)
        XCTAssertEqual(uiKitMock.continueNSUserActivityCallsCount, 2)
        XCTAssertFalse(uiKitMock.openCalled)
    }

    func test_handleDeepLink_givenHostAppDoesNotHandleDeepLink() {
        uiKitMock.continueNSUserActivityReturnValue = false

        deepLinkUtil.handleDeepLink(URL(string: "https://customer.io")!, deepLinkDelegate: nil)

        XCTAssertFalse(deepLinkDelegateMock.onOpenDeepLinkCalled)
        XCTAssertEqual(uiKitMock.continueNSUserActivityCallsCount, 1)
        XCTAssertEqual(uiKitMock.openCallsCount, 1)

        // Same behavior expected when delegate returns false
        uiKitMock.continueNSUserActivityReturnValue = false
        deepLinkDelegateMock.onOpenDeepLinkReturnValue = false

        deepLinkUtil.handleDeepLink(URL(string: "https://customer.io")!, deepLinkDelegate: deepLinkDelegateMock)

        XCTAssertEqual(deepLinkDelegateMock.onOpenDeepLinkCallsCount, 1)
        XCTAssertEqual(uiKitMock.continueNSUserActivityCallsCount, 2)
        XCTAssertEqual(uiKitMock.openCallsCount, 1)
    }
}
