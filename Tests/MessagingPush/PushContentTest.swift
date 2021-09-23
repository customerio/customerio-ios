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
}
#endif
