import CioInternalCommon
@testable import CioMessagingPush
@testable import CioTracking
import Foundation
import SharedTests
import UserNotifications
import XCTest

class PushClickHandlerTest: UnitTest {
    private var pushClickHandler: PushClickHandler!

    private let deepLinkUtilMock = DeepLinkUtilMock()
    private let pushHistoryMock = PushHistoryMock()
    private let customerIOMock = CustomerIOInstanceMock()

    override func setUp() {
        super.setUp()

        setupTest(autoTrackPushEvents: sdkConfig.autoTrackPushEvents)
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

    func test_pushClicked_givenEnabledAutomaticPushEvents_expectTrackOpenedEvent() {
        setupTest(autoTrackPushEvents: true)

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

    func test_pushClicked_givenDisableAutomaticPushEvents_expectDoNotTrackOpenedEvent() {
        setupTest(autoTrackPushEvents: false)

        let givenPush = getPush(content: [
            "CIO": [
                "push": [
                    "image": "https://example.com/image.png"
                ]
            ]
        ])

        pushClickHandler.pushClicked(givenPush)

        XCTAssertEqual(customerIOMock.trackMetricCallsCount, 0)
    }

    func test_pushClicked_expectIgnoreRequestIfAlreadyHandledPush() {
        setupTest(autoTrackPushEvents: true) // using push tracking as our indicator if a request is ignored

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

extension PushClickHandlerTest {
    func setupTest(autoTrackPushEvents: Bool) {
        super.setUp(modifySdkConfig: { config in
            config.autoTrackPushEvents = autoTrackPushEvents
        })

        // Set default values of mocks to avoid having to add to every test function.
        pushHistoryMock.hasHandledPushClickReturnValue = false

        pushClickHandler = PushClickHandlerImpl(sdkConfig: sdkConfig, deepLinkUtil: deepLinkUtilMock, pushHistory: pushHistoryMock, customerIO: customerIOMock)
    }

    func getPush(content: [AnyHashable: Any], deliveryId: String = .random, deviceToken: String = .random) -> CustomerIOParsedPushPayload {
        var content = content

        let notificationContent = UNNotificationContent().mutableCopy() as! UNMutableNotificationContent

        content["CIO-Delivery-ID"] = deliveryId
        content["CIO-Delivery-Token"] = deviceToken

        notificationContent.userInfo = content

        return CustomerIOParsedPushPayload.parse(notificationContent: notificationContent, jsonAdapter: jsonAdapter)!
    }
}
