@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

class PushNotificationTest: UnitTest {
    // MARK: Test a push notification not sent from CIO

    func test_notCioPush_expectCioGettersReturnNil() {
        let givenPush = PushNotificationStub.getPushNotSentFromCIO()

        XCTAssertFalse(givenPush.isPushSentFromCio)
        XCTAssertNil(givenPush.cioDelivery)
        XCTAssertNil(givenPush.cioImage)
        XCTAssertNil(givenPush.cioDeepLink)
    }

    // MARK: Test a push notification sent from CIO

    func test_givenSimpleCioPush_expectCioGettersReturnParsedValues() {
        let givenDeliveryId = String.random
        let givenDeviceToken = String.random

        let givenPush = PushNotificationStub.getPushSentFromCIO(
            deliveryId: givenDeliveryId,
            deviceToken: givenDeviceToken,
            deepLink: nil,
            imageUrl: nil
        )

        XCTAssertTrue(givenPush.isPushSentFromCio)
        XCTAssertEqual(givenPush.cioDelivery?.id, givenDeliveryId)
        XCTAssertEqual(givenPush.cioDelivery?.token, givenDeviceToken)
        XCTAssertNil(givenPush.cioImage)
        XCTAssertNil(givenPush.cioDeepLink)
    }

    func test_givenRichCioPush_expectCioGettersReturnParsedValues() {
        let givenDeepLink = "https://customer.io"
        let givenImageUrl = "https://customer.io/image.png"
        let givenDeliveryId = String.random
        let givenDeviceToken = String.random

        let givenPush = PushNotificationStub.getPushSentFromCIO(
            deliveryId: givenDeliveryId,
            deviceToken: givenDeviceToken,
            deepLink: givenDeepLink,
            imageUrl: givenImageUrl
        )

        XCTAssertTrue(givenPush.isPushSentFromCio)
        XCTAssertEqual(givenPush.cioDelivery?.id, givenDeliveryId)
        XCTAssertEqual(givenPush.cioDelivery?.token, givenDeviceToken)
        XCTAssertEqual(givenPush.cioImage, givenImageUrl)
        XCTAssertEqual(givenPush.cioDeepLink, givenDeepLink)
    }

    func test_cioPush_givenSetRichPushImageFile_expectPushAttachmentAdded() {
        var givenPush = PushNotificationStub.getPushSentFromCIO()
        let givenImageFileUrl = URL(fileURLWithPath: String.random)

        // Important to check both attachment properties.
        // Checks that the SDK code is able to differentiate between attachments added by our SDK and not.
        XCTAssertTrue(givenPush.attachments.isEmpty)
        XCTAssertTrue(givenPush.cioAttachments.isEmpty)

        givenPush.cioRichPushImageFile = givenImageFileUrl

        XCTAssertEqual(givenPush.attachments.count, 1)
        XCTAssertEqual(givenPush.cioAttachments.count, 1)
        XCTAssertEqual(givenPush.attachments.first?.localFileUrl, givenImageFileUrl)
    }
}
