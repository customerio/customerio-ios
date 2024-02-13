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
    private let messagingPushMock = MessagingPushInstanceMock()

    override func setUp() {
        super.setUp()

        pushClickHandler = PushClickHandlerImpl(deepLinkUtil: deepLinkUtilMock, messagingPush: messagingPushMock)
    }

    // MARK: pushClicked

    func test_pushClicked_givenNoDeepLinkAttached_expectDoNotHandleDeepLink() {
        let givenPush = PushNotificationStub.getPushSentFromCIO(imageUrl: "https://example.com/image.png")

        pushClickHandler.pushClicked(givenPush)

        XCTAssertFalse(deepLinkUtilMock.mockCalled)
    }

    func test_pushClicked_givenDeepLinkAttached_expectHandleDeepLink() {
        let givenDeepLink = "https://example.com/\(String.random)"
        let givenPush = PushNotificationStub.getPushSentFromCIO(deepLink: givenDeepLink, imageUrl: "https://example.com/image.png")

        pushClickHandler.pushClicked(givenPush)

        XCTAssertEqual(deepLinkUtilMock.handleDeepLinkCallsCount, 1)
        XCTAssertEqual(deepLinkUtilMock.handleDeepLinkReceivedArguments, URL(string: givenDeepLink))
    }

    func test_pushClicked_expectTrackOpenedEvent() {
        let givenPush = PushNotificationStub.getPushSentFromCIO(imageUrl: "https://example.com/image.png")

        pushClickHandler.pushClicked(givenPush)

        XCTAssertEqual(messagingPushMock.trackMetricCallsCount, 1)
    }
}
