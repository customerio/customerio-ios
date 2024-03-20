@testable import CioMessagingPush
import SharedTests
import XCTest

class MessagingPushConfigBuilderTest: UnitTest {
    func test_initializeAndDoNotModify_expectDefaultValues() {
        let config = MessagingPushConfigBuilder().build()

        XCTAssertDefaultValues(config: config)
    }

    func test_initializeAndModify_expectCustomValues() {
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

    func test_initializeFromEmptyDictionary_expectDefaultValues() {
        let givenDict: [String: Any] = [:]

        let config = MessagingPushConfigBuilder.build(from: givenDict)

        XCTAssertDefaultValues(config: config)
    }

    func test_initializeFromDictionaryWithCustomValues_expectCustomValues() {
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

    func test_initializeFromDictionaryWithIncorrectKeys_expectDefaultValues() {
        let givenDict: [String: Any] = [
            "fetchDeviceToken": false,
            "trackPushEvents": false,
            "pushAppInForeground": false
        ]

        let config = MessagingPushConfigBuilder.build(from: givenDict)

        XCTAssertDefaultValues(config: config)
    }

    func test_initializeFromDictionaryWithIncorrectValues_expectDefaultValues() {
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
    private func XCTAssertDefaultValues(config: MessagingPushConfigOptions, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(config.logLevel, .error, file: file, line: line)
        XCTAssertTrue(config.autoFetchDeviceToken, file: file, line: line)
        XCTAssertTrue(config.autoTrackPushEvents, file: file, line: line)
        XCTAssertTrue(config.showPushAppInForeground, file: file, line: line)
    }
}
