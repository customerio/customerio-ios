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

    func test_initializeFromDictionaryWithIncorrectRegionType_expectThrowError() {
        let givenSiteId = String.random
        let givenDict: [String: Any] = [
            "region": Region.US,
            "inApp": [
                "siteId": givenSiteId
            ]
        ]

        XCTAssertThrowsError(try MessagingInAppConfigBuilder.build(from: givenDict)) { error in
            XCTAssertEqual(error as? MessagingInAppConfigBuilderError, MessagingInAppConfigBuilderError.invalidRegionType)
        }
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
