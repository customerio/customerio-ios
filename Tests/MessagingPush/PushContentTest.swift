@testable import CioMessagingPush
@testable import CioTracking
import Foundation
import SharedTests
import XCTest
#if canImport(UserNotifications)
import UserNotifications

class PushContentTest: UnitTest {
    var validCioPushContent: [AnyHashable: Any] = ["CIO": [
        "push": [
            "link": String.random
        ]
    ]]

    // MARK: parse

    func test_parse_givenPushWithoutCioContent_expectNil() {
        let givenContent = UNMutableNotificationContent()
        givenContent.userInfo = ["aps": ["mutable-content": 1]]

        XCTAssertNil(PushContent.parse(notificationContent: givenContent, jsonAdapter: jsonAdapter))
    }

    func test_parse_givenPushNotContainingValidCioContent_expectNil() {
        let givenContent = UNMutableNotificationContent()
        givenContent.userInfo = ["CIO": [
            "not-push": [
                "link": "cio://foo"
            ]
        ]]

        XCTAssertNil(PushContent.parse(notificationContent: givenContent, jsonAdapter: jsonAdapter))
    }

    func test_parse_givenCioPushContent_expectObject() {
        let givenLink = "cio://\(String.random)"
        let givenContent = UNMutableNotificationContent()
        givenContent.userInfo = ["CIO": [
            "push": [
                "link": givenLink
            ]
        ]]

        let actual = PushContent.parse(notificationContent: givenContent, jsonAdapter: jsonAdapter)!

        XCTAssertEqual(actual.deepLink!, givenLink.url!)
    }

    // MARK: addImage

    func test_addImage_givenMultipleImages_expectAddAll() {
        let content = UNMutableNotificationContent()
        content.userInfo = validCioPushContent
        let pushContent = PushContent.parse(notificationContent: content, jsonAdapter: jsonAdapter)!

        pushContent.addImage(localFilePath: "https://customer.io/\(String.random).jpg".url!)

        XCTAssertEqual(pushContent.mutableNotificationContent.attachments.count, 1)

        pushContent.addImage(localFilePath: "https://customer.io/\(String.random).jpg".url!)

        XCTAssertEqual(pushContent.mutableNotificationContent.attachments.count, 2)
    }

    func test_addImage_givenImage_expectUseFilenameOfImage() {
        let content = UNMutableNotificationContent()
        content.userInfo = validCioPushContent
        let pushContent = PushContent.parse(notificationContent: content, jsonAdapter: jsonAdapter)!

        let givenImageUrl = "https://customer.io/\(String.random).jpg".url!

        pushContent.addImage(localFilePath: givenImageUrl)

        XCTAssertEqual(pushContent.mutableNotificationContent.attachments[0].identifier,
                       givenImageUrl.absoluteString.fileName)
    }

    // MARK: property setters/getters

    func test_title_givenSet_expectGetSameValue() {
        let given = String.random
        let content = UNMutableNotificationContent()
        content.title = "foo"
        content.userInfo = validCioPushContent
        let pushContent = PushContent.parse(notificationContent: content, jsonAdapter: jsonAdapter)!

        XCTAssertNotEqual(given, pushContent.title)

        pushContent.title = given

        XCTAssertEqual(given, pushContent.title)
    }

    func test_body_givenSet_expectGetSameValue() {
        let given = String.random
        let content = UNMutableNotificationContent()
        content.body = "foo"
        content.userInfo = validCioPushContent
        let pushContent = PushContent.parse(notificationContent: content, jsonAdapter: jsonAdapter)!

        XCTAssertNotEqual(given, pushContent.body)

        pushContent.body = given

        XCTAssertEqual(given, pushContent.body)
    }

    func test_deepLink_givenSet_expectGetSameValue() {
        let given = "cio://\(String.random)".url
        let content = UNMutableNotificationContent()
        content.userInfo = validCioPushContent
        let pushContent = PushContent.parse(notificationContent: content, jsonAdapter: jsonAdapter)!

        XCTAssertNotEqual(given, pushContent.deepLink)

        pushContent.deepLink = given

        XCTAssertEqual(given, pushContent.deepLink)
    }

    func test_image_givenSet_expectGetSameValue() {
        let given = "https://\(String.random).jpg".url
        let content = UNMutableNotificationContent()
        content.userInfo = validCioPushContent
        let pushContent = PushContent.parse(notificationContent: content, jsonAdapter: jsonAdapter)!

        XCTAssertNotEqual(given, pushContent.image)

        pushContent.image = given

        XCTAssertEqual(given, pushContent.image)
    }
}
#endif
