import CioInternalCommon
@testable import CioMessagingInApp
import SharedTests
import XCTest

class MessagingInAppConfigBuilderTest: UnitTest {
    func test_initializeAndModify_expectCustomValues() {
        let givenSiteId = String.random

        let config = MessagingInAppConfigBuilder(siteId: givenSiteId).build()

        XCTAssertEqual(config.siteId, givenSiteId)
    }

    // Apps already built with a region still compile. The region is kept on the config but not used.
    @available(*, deprecated)
    func test_initialize_givenDeprecatedRegion_expectSiteIdAndRegionKept() {
        let config = MessagingInAppConfigBuilder(siteId: "site-1", region: .EU).build()

        XCTAssertEqual(config.siteId, "site-1")
        XCTAssertEqual(config.region, .EU)
    }

    func test_build_givenNoNotificationInboxAccessibilityLabels_expectAllNil() {
        let config = MessagingInAppConfigBuilder(siteId: String.random).build()

        XCTAssertNil(config.notificationInboxAccessibilityLabels.bell)
        XCTAssertNil(config.notificationInboxAccessibilityLabels.bellWithUnreadCount)
        XCTAssertNil(config.notificationInboxAccessibilityLabels.loadingIndicator)
        XCTAssertNil(config.notificationInboxAccessibilityLabels.emptyState)
    }

    func test_setNotificationInboxAccessibilityLabels_expectLabelsOnConfig() {
        let config = MessagingInAppConfigBuilder(siteId: String.random)
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

    @available(*, deprecated)
    func test_initializeFromDictionaryWithCustomValues_expectRegionNotRead() {
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
        // Region comes from the SDK setup instead.
        XCTAssertEqual(config?.region, .US)
    }

    func test_initializeFromEmptyDictionary_expectConfigWithoutSiteId() throws {
        let givenDict: [String: Any] = [
            "inApp": [:]
        ]

        let config = try MessagingInAppConfigBuilder.build(from: givenDict)

        XCTAssertEqual(config?.siteId, "")
    }

    func test_initializeFromDictionaryWithEmptySiteId_expectConfigWithoutSiteId() throws {
        let givenDict: [String: Any] = [
            "inApp": [
                "siteId": ""
            ]
        ]

        let config = try MessagingInAppConfigBuilder.build(from: givenDict)

        XCTAssertEqual(config?.siteId, "")
    }

    func test_init_givenNoSiteId_expectEmptySiteIdAndDefaults() {
        let config = MessagingInAppConfigBuilder().build()

        XCTAssertEqual(config.siteId, "")
        XCTAssertEqual(config.colorScheme, .auto)
    }

    // Apps written against the old API read `siteId` as a non-optional `String`.
    func test_siteId_givenLegacyCaller_expectNonOptionalString() {
        let config = MessagingInAppConfigBuilder(siteId: "site-1").build()

        let siteId: String = config.siteId

        XCTAssertEqual(siteId, "site-1")
    }

    func test_initializeFromDictionaryWithoutSiteId_givenPublicKey_expectConfigWithoutSiteId() throws {
        let givenDict: [String: Any] = [
            "cdpApiKey": "pk_us_\(String.random)",
            "inApp": [
                "colorScheme": "dark"
            ]
        ]

        let config = try MessagingInAppConfigBuilder.build(from: givenDict)

        XCTAssertEqual(config?.siteId, "")
        XCTAssertEqual(config?.colorScheme, .dark)
    }

    func test_initializeFromMalformedDictionary_expectThrowError() {
        let givenDict: [String: Any] = [
            "inApp": String.random
        ]

        XCTAssertThrowsError(try MessagingInAppConfigBuilder.build(from: givenDict)) { error in
            XCTAssertEqual(error as? MessagingInAppConfigBuilderError, MessagingInAppConfigBuilderError.malformedConfig)
        }
    }

    @available(*, deprecated)
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

    func test_initializeFromDictionaryWithIncorrectSiteIdType_expectConfigWithoutSiteId() throws {
        let givenDict: [String: Any] = [
            "region": "US",
            "inApp": [
                "siteId": 100
            ]
        ]

        let config = try MessagingInAppConfigBuilder.build(from: givenDict)

        XCTAssertEqual(config?.siteId, "")
    }

    @available(*, deprecated)
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

    @available(*, deprecated)
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
