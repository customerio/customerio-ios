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

    // MARK: handleDeepLink

    func test_handleDeepLink_givenNoDeepLinkAttached_expectDoNotHandleDeepLink() {
        let givenPush = PushNotificationStub.getPushSentFromCIO(imageUrl: "https://example.com/image.png")

        pushClickHandler.handleDeepLink(for: givenPush)

        XCTAssertFalse(deepLinkUtilMock.mockCalled)
    }

    func test_handleDeepLink_givenDeepLinkAttached_expectHandleDeepLink() {
        let givenDeepLink = "https://example.com/\(String.random)"
        let givenPush = PushNotificationStub.getPushSentFromCIO(deepLink: givenDeepLink, imageUrl: "https://example.com/image.png")

        pushClickHandler.handleDeepLink(for: givenPush)

        XCTAssertEqual(deepLinkUtilMock.handleDeepLinkCallsCount, 1)
        XCTAssertEqual(deepLinkUtilMock.handleDeepLinkReceivedArguments, URL(string: givenDeepLink))
    }

    // MARK: trackPushMetrics

    func test_trackPushMetrics_expectTrackOpenedEvent() {
        let givenPush = PushNotificationStub.getPushSentFromCIO(imageUrl: "https://example.com/image.png")

        pushClickHandler.trackPushMetrics(for: givenPush)

        XCTAssertEqual(customerIOMock.trackMetricCallsCount, 1)
    }
}
