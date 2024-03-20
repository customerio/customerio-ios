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

    func test_initializeFromDictionaryWithCustomValues_expectCustomValues() {
        let givenSiteId = String.random
        let givenRegion = "EU"

        let givenDict: [String: Any] = [
            "siteId": givenSiteId,
            "region": givenRegion
        ]

        let config = try? MessagingInAppConfigBuilder.build(from: givenDict)

        XCTAssertNotNil(config)
        XCTAssertEqual(config?.siteId, givenSiteId)
        XCTAssertEqual(config?.region.rawValue, givenRegion)
    }

    func test_initializeFromEmptyDictionary_expectThrowError() {
        let givenDict: [String: Any] = [:]

        XCTAssertThrowsError(try MessagingInAppConfigBuilder.build(from: givenDict)) { error in
            XCTAssertEqual(error as? MessagingInAppConfigBuilderError, MessagingInAppConfigBuilderError.missingSiteId)
        }
    }

    func test_initializeFromDictionaryWithOnlySiteId_expectThrowError() {
        let givenDict: [String: Any] = [
            "siteId": String.random
        ]

        XCTAssertThrowsError(try MessagingInAppConfigBuilder.build(from: givenDict)) { error in
            XCTAssertEqual(error as? MessagingInAppConfigBuilderError, MessagingInAppConfigBuilderError.missingRegion)
        }
    }

    func test_initializeFromDictionaryWithIncorrectSiteIdType_expectThrowError() {
        let givenDict: [String: Any] = [
            "siteId": 100,
            "region": "US"
        ]

        XCTAssertThrowsError(try MessagingInAppConfigBuilder.build(from: givenDict)) { error in
            XCTAssertEqual(error as? MessagingInAppConfigBuilderError, MessagingInAppConfigBuilderError.missingSiteId)
        }
    }

    func test_initializeFromDictionaryWithOnlyRegion_expectThrowError() {
        let givenDict: [String: Any] = [
            "region": String.random
        ]

        XCTAssertThrowsError(try MessagingInAppConfigBuilder.build(from: givenDict)) { error in
            XCTAssertEqual(error as? MessagingInAppConfigBuilderError, MessagingInAppConfigBuilderError.missingSiteId)
        }
    }

    func test_initializeFromDictionaryWithIncorrectRegionType_expectThrowError() {
        let givenSiteId = String.random
        let givenDict: [String: Any] = [
            "siteId": givenSiteId,
            "region": Region.US
        ]

        XCTAssertThrowsError(try MessagingInAppConfigBuilder.build(from: givenDict)) { error in
            XCTAssertEqual(error as? MessagingInAppConfigBuilderError, MessagingInAppConfigBuilderError.missingRegion)
        }
    }

    func test_initializeFromDictionaryWithIncorrectRegionValue_expectDefaultValues() {
        let givenSiteId = String.random
        let givenDict: [String: Any] = [
            "siteId": givenSiteId,
            "region": "OK"
        ]

        let config = try? MessagingInAppConfigBuilder.build(from: givenDict)

        XCTAssertNotNil(config)
        XCTAssertEqual(config?.siteId, givenSiteId)
        XCTAssertEqual(config?.region, Region.US)
    }
}
