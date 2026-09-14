import CioInternalCommon
@testable import CioMessagingInApp
import SharedTests
import XCTest

class MessagingInAppConfigBuilderTest: UnitTest {
    func test_initializeAndModify_expectCustomValues() {
        let givenSiteId = String.random
        let givenRegion = Region.EU

        let config = MessagingInAppConfigBuilder(siteId: givenSiteId, region: givenRegion).build()

        XCTAssertEqual(config.siteId, givenSiteId)
        XCTAssertEqual(config.region, givenRegion)
    }

    func test_build_givenNoNotificationInboxAccessibilityLabels_expectAllNil() {
        let config = MessagingInAppConfigBuilder(siteId: String.random, region: .US).build()

        XCTAssertNil(config.notificationInboxAccessibilityLabels.bell)
        XCTAssertNil(config.notificationInboxAccessibilityLabels.bellWithUnreadCount)
        XCTAssertNil(config.notificationInboxAccessibilityLabels.loadingIndicator)
        XCTAssertNil(config.notificationInboxAccessibilityLabels.emptyState)
    }

    func test_setNotificationInboxAccessibilityLabels_expectLabelsOnConfig() {
        let config = MessagingInAppConfigBuilder(siteId: String.random, region: .US)
            .setNotificationInboxAccessibilityLabels(NotificationInboxAccessibilityLabels(
                bell: "Aviseringar",
                bellWithUnreadCount: { count in count == 1 ? "1 oläst avisering" : "\(count) olästa aviseringar" },
                loadingIndicator: "Laddar",
                emptyState: "Inga aviseringar"
            ))
            .build()

        XCTAssertEqual(config.notificationInboxAccessibilityLabels.bell, "Aviseringar")
        XCTAssertEqual(config.notificationInboxAccessibilityLabels.bellWithUnreadCount?(1), "1 oläst avisering")
        XCTAssertEqual(config.notificationInboxAccessibilityLabels.bellWithUnreadCount?(4), "4 olästa aviseringar")
        XCTAssertEqual(config.notificationInboxAccessibilityLabels.loadingIndicator, "Laddar")
        XCTAssertEqual(config.notificationInboxAccessibilityLabels.emptyState, "Inga aviseringar")
    }

    func test_initializeFromDictionaryWithNotificationInboxAccessibilityLabels_expectLabelsAndTemplate() throws {
        let givenDict: [String: Any] = [
            "inApp": [
                "siteId": String.random,
                "notificationInboxAccessibilityLabels": [
                    "bell": "Aviseringar",
                    "bellWithUnreadCount": "{count} olästa aviseringar",
                    "loadingIndicator": "Laddar",
                    "emptyState": "Inga aviseringar"
                ]
            ]
        ]

        let config = try XCTUnwrap(MessagingInAppConfigBuilder.build(from: givenDict))

        XCTAssertEqual(config.notificationInboxAccessibilityLabels.bell, "Aviseringar")
        XCTAssertEqual(config.notificationInboxAccessibilityLabels.bellWithUnreadCount?(2), "2 olästa aviseringar")
        XCTAssertEqual(config.notificationInboxAccessibilityLabels.loadingIndicator, "Laddar")
        XCTAssertEqual(config.notificationInboxAccessibilityLabels.emptyState, "Inga aviseringar")
    }

    func test_initializeFromDictionaryWithPartialNotificationInboxAccessibilityLabels_expectMissingAndNonStringNil() throws {
        let givenDict: [String: Any] = [
            "inApp": [
                "siteId": String.random,
                "notificationInboxAccessibilityLabels": [
                    "emptyState": "Inga aviseringar",
                    "bell": 42
                ]
            ]
        ]

        let config = try XCTUnwrap(MessagingInAppConfigBuilder.build(from: givenDict))

        XCTAssertNil(config.notificationInboxAccessibilityLabels.bell)
        XCTAssertNil(config.notificationInboxAccessibilityLabels.bellWithUnreadCount)
        XCTAssertNil(config.notificationInboxAccessibilityLabels.loadingIndicator)
        XCTAssertEqual(config.notificationInboxAccessibilityLabels.emptyState, "Inga aviseringar")
    }

    func test_initializeFromDictionaryWithoutNotificationInboxAccessibilityLabels_expectAllNil() throws {
        let givenDict: [String: Any] = [
            "inApp": [
                "siteId": String.random
            ]
        ]

        let config = try XCTUnwrap(MessagingInAppConfigBuilder.build(from: givenDict))

        XCTAssertNil(config.notificationInboxAccessibilityLabels.bell)
        XCTAssertNil(config.notificationInboxAccessibilityLabels.bellWithUnreadCount)
        XCTAssertNil(config.notificationInboxAccessibilityLabels.loadingIndicator)
        XCTAssertNil(config.notificationInboxAccessibilityLabels.emptyState)
    }

    func test_initializeFromDictionaryWithCustomValues_expectCorrectValues() {
        let givenSiteId = String.random
        let givenRegion = "EU"

        let givenDict: [String: Any] = [
            "region": givenRegion,
            "inApp": [
                "siteId": givenSiteId
            ]
        ]

        let config = try? MessagingInAppConfigBuilder.build(from: givenDict)

        XCTAssertNotNil(config)
        XCTAssertEqual(config?.siteId, givenSiteId)
        XCTAssertEqual(config?.region.rawValue, givenRegion)
    }

    func test_initializeFromEmptyDictionary_expectThrowError() {
        let givenDict: [String: Any] = [
            "inApp": [:]
        ]

        XCTAssertThrowsError(try MessagingInAppConfigBuilder.build(from: givenDict)) { error in
            XCTAssertEqual(error as? MessagingInAppConfigBuilderError, MessagingInAppConfigBuilderError.missingSiteId)
        }
    }

    func test_initializeFromMalformedDictionary_expectThrowError() {
        let givenDict: [String: Any] = [
            "inApp": String.random
        ]

        XCTAssertThrowsError(try MessagingInAppConfigBuilder.build(from: givenDict)) { error in
            XCTAssertEqual(error as? MessagingInAppConfigBuilderError, MessagingInAppConfigBuilderError.malformedConfig)
        }
    }

    func test_initializeFromDictionaryWithOnlySiteId_expectConfigWithDefaultRegion() {
        let givenSiteId = String.random
        let givenDict: [String: Any] = [
            "inApp": [
                "siteId": givenSiteId
            ]
        ]

        let config = try? MessagingInAppConfigBuilder.build(from: givenDict)

        XCTAssertNotNil(config)
        XCTAssertEqual(config?.siteId, givenSiteId)
        XCTAssertEqual(config?.region, .US)
    }

    func test_initializeFromDictionaryWithIncorrectSiteIdType_expectThrowError() {
        let givenDict: [String: Any] = [
            "region": "US",
            "inApp": [
                "siteId": 100
            ]
        ]

        XCTAssertThrowsError(try MessagingInAppConfigBuilder.build(from: givenDict)) { error in
            XCTAssertEqual(error as? MessagingInAppConfigBuilderError, MessagingInAppConfigBuilderError.missingSiteId)
        }
    }

    func test_initializeFromDictionaryWithOnlyRegion_expectThrowError() {
        let givenDict: [String: Any] = [
            "region": String.random,
            "inApp": [
                "apiKey": String.random
            ]
        ]

        XCTAssertThrowsError(try MessagingInAppConfigBuilder.build(from: givenDict)) { error in
            XCTAssertEqual(error as? MessagingInAppConfigBuilderError, MessagingInAppConfigBuilderError.missingSiteId)
        }
    }

    func test_initializeFromDictionaryWithIncorrectRegionType_expectDefaultValues() {
        let givenSiteId = String.random
        let givenDict: [String: Any] = [
            "region": NSNull(),
            "inApp": [
                "siteId": givenSiteId
            ]
        ]

        let config = try? MessagingInAppConfigBuilder.build(from: givenDict)

        XCTAssertNotNil(config)
        XCTAssertEqual(config?.siteId, givenSiteId)
        XCTAssertEqual(config?.region, Region.US)
    }

    func test_initializeFromDictionaryWithIncorrectRegionValue_expectDefaultValues() {
        let givenSiteId = String.random
        let givenDict: [String: Any] = [
            "region": "OK",
            "inApp": [
                "siteId": givenSiteId
            ]
        ]

        let config = try? MessagingInAppConfigBuilder.build(from: givenDict)

        XCTAssertNotNil(config)
        XCTAssertEqual(config?.siteId, givenSiteId)
        XCTAssertEqual(config?.region, Region.US)
    }
}
