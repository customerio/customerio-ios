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
    private let pushHistoryMock = PushHistoryMock()
    private let customerIOMock = CustomerIOInstanceMock()

    override func setUp() {
        super.setUp()

        // Set default values of mocks to avoid having to add to every test function.
        pushHistoryMock.hasHandledPushClickReturnValue = false

        pushClickHandler = PushClickHandlerImpl(deepLinkUtil: deepLinkUtilMock, pushHistory: pushHistoryMock, customerIO: customerIOMock)
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

    func test_pushClicked_expectIgnoreRequestIfAlreadyHandledPush() {
        // Note: Using push tracking as our indicator if a request is ignored

        // Indicate we have already processed the push
        pushHistoryMock.hasHandledPushClickReturnValue = true

        let givenPush = getPush(content: [
            "CIO": [
                "push": [
                    "image": "https://example.com/image.png"
                ]
            ]
        ])

        pushClickHandler.pushClicked(givenPush)

        // Assert request was ignored
        XCTAssertEqual(customerIOMock.trackMetricCallsCount, 0)

        // To be thorough, call again and make sure assertions change as expected
        pushHistoryMock.hasHandledPushClickReturnValue = false
        pushClickHandler.pushClicked(givenPush)
        XCTAssertEqual(customerIOMock.trackMetricCallsCount, 1)
    }
}
