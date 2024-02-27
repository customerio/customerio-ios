@testable import CioMessagingPush
import SharedTests
import XCTest

class MessagingPushConfigBuilderTest: UnitTest {
    func test_defaultInitialization_expectDefaultValues() {
        let config = MessagingPushConfigBuilder().build()

        XCTAssertDefaultValues(config: config)
    }

    func test_modifiedConfiguration_expectCustomValues() {
        let givenAutoFetchDeviceToken = false
        let givenAutoTrackPushEvents = false
        let givenShowPushAppInForeground = false

        let config = MessagingPushConfigBuilder()
            .autoFetchDeviceToken(givenAutoFetchDeviceToken)
            .autoTrackPushEvents(givenAutoTrackPushEvents)
            .showPushAppInForeground(givenShowPushAppInForeground)
            .build()

        XCTAssertEqual(config.autoFetchDeviceToken, givenAutoFetchDeviceToken)
        XCTAssertEqual(config.autoTrackPushEvents, givenAutoTrackPushEvents)
        XCTAssertEqual(config.showPushAppInForeground, givenShowPushAppInForeground)
    }

    func test_initializationWithEmptyDict_expectDefaultValues() {
        let givenDict: [String: Any] = [:]

        let config = MessagingPushConfigBuilder.build(from: givenDict)

        XCTAssertDefaultValues(config: config)
    }

    func test_mapInitializationWithCustomValues_expectCustomValues() {
        let givenAutoFetchDeviceToken = false
        let givenAutoTrackPushEvents = false
        let givenShowPushAppInForeground = false

        let givenDict: [String: Any] = [
            "autoFetchDeviceToken": givenAutoFetchDeviceToken,
            "autoTrackPushEvents": givenAutoTrackPushEvents,
            "showPushAppInForeground": givenShowPushAppInForeground
        ]

        let config = MessagingPushConfigBuilder.build(from: givenDict)

        XCTAssertEqual(config.autoFetchDeviceToken, givenAutoFetchDeviceToken)
        XCTAssertEqual(config.autoTrackPushEvents, givenAutoTrackPushEvents)
        XCTAssertEqual(config.showPushAppInForeground, givenShowPushAppInForeground)
    }

    func test_mapInitializationWithIncorrectKeys_expectDefaultValues() {
        let givenDict: [String: Any] = [
            "fetchDeviceToken": false,
            "trackPushEvents": false,
            "pushAppInForeground": false
        ]

        let config = MessagingPushConfigBuilder.build(from: givenDict)

        XCTAssertDefaultValues(config: config)
    }

    func test_mapInitializationWithIncorrectValues_expectDefaultValues() {
        let givenDict: [String: Any] = [
            "autoFetchDeviceToken": 123,
            "autoTrackPushEvents": "false",
            "showPushAppInForeground": 20.0
        ]

        let config = MessagingPushConfigBuilder.build(from: givenDict)

        XCTAssertDefaultValues(config: config)
    }
}

extension MessagingPushConfigBuilderTest {
    // Extension method to conveniently assert default values.
    private func XCTAssertDefaultValues(config: MessagingPushConfigOptions) {
        XCTAssertTrue(config.autoFetchDeviceToken)
        XCTAssertTrue(config.autoTrackPushEvents)
        XCTAssertTrue(config.showPushAppInForeground)
    }
}
