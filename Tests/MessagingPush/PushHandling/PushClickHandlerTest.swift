import CioInternalCommon
@testable import CioMessagingPush
@testable import CioTracking
import Foundation
import SharedTests
import UserNotifications
import XCTest

class PushClickHandlerTest: IntegrationTest {
    private var pushClickHandler: PushClickHandler!

    private let deepLinkUtilMock = DeepLinkUtilMock()
    private let customerIOMock = CustomerIOInstanceMock()

    override func setUp() {
        super.setUp()

        pushClickHandler = PushClickHandlerImpl(deepLinkUtil: deepLinkUtilMock, customerIO: customerIOMock)
    }

    // MARK: pushClicked

    func test_pushClicked_givenNoDeepLinkAttached_expectDoNotHandleDeepLink() {
        let givenPush = getPush(content: [
            "CIO": [
                "push": [
                    "image": "https://example.com/image.png"
                ]
            ]
        ])

        pushClickHandler.pushClicked(givenPush)

        XCTAssertFalse(deepLinkUtilMock.mockCalled)
    }

    func test_pushClicked_givenDeepLinkAttached_expectHandleDeepLink() {
        let givenDeepLink = "https://example.com/\(String.random)"

        let givenPush = getPush(content: [
            "CIO": [
                "push": [
                    "link": givenDeepLink,
                    "image": "https://example.com/image.png"
                ]
            ]
        ])

        pushClickHandler.pushClicked(givenPush)

        XCTAssertEqual(deepLinkUtilMock.handleDeepLinkCallsCount, 1)
        XCTAssertEqual(deepLinkUtilMock.handleDeepLinkReceivedArguments, URL(string: givenDeepLink))
    }

    func test_pushClicked_expectTrackOpenedEvent() {
        let givenPush = getPush(content: [
            "CIO": [
                "push": [
                    "image": "https://example.com/image.png"
                ]
            ]
        ])

        pushClickHandler.pushClicked(givenPush)

        XCTAssertEqual(customerIOMock.trackMetricCallsCount, 1)
    }
}