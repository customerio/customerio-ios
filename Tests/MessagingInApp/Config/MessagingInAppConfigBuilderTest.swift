import CioInternalCommon
@testable import CioMessagingInApp
import SharedTests
import XCTest

class MessagingInAppConfigBuilderTest: UnitTest {
    func test_modifiedConfiguration_expectCustomValues() {
        let givenSiteId = String.random
        let givenRegion = Region.EU

        let config = MessagingInAppConfigBuilder(siteId: givenSiteId, region: givenRegion).build()

        XCTAssertEqual(config.siteId, givenSiteId)
        XCTAssertEqual(config.region, givenRegion)
    }

    func test_mapInitializationWithCustomValues_expectCustomValues() {
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

    func test_initializationWithEmptyDict_expectThrowError() {
        let givenDict: [String: Any] = [:]

        XCTAssertThrowsError(try MessagingInAppConfigBuilder.build(from: givenDict)) { error in
            XCTAssertEqual(error as? MessagingInAppConfigBuilderError, MessagingInAppConfigBuilderError.missingSiteId)
        }
    }

    func test_initializationWithOnlySiteId_expectDefaultRegion() {
        let givenSiteId = String.random
        let givenDict: [String: Any] = [
            "siteId": givenSiteId
        ]

        let config = try? MessagingInAppConfigBuilder.build(from: givenDict)

        XCTAssertNotNil(config)
        XCTAssertEqual(config?.siteId, givenSiteId)
        XCTAssertEqual(config?.region, Region.US)
    }

    func test_mapInitializationWithIncorrectSiteIdType_expectThrowError() {
        let givenDict: [String: Any] = [
            "siteId": 100,
            "region": "US"
        ]

        XCTAssertThrowsError(try MessagingInAppConfigBuilder.build(from: givenDict)) { error in
            XCTAssertEqual(error as? MessagingInAppConfigBuilderError, MessagingInAppConfigBuilderError.missingSiteId)
        }
    }

    func test_initializationWithOnlyRegion_expectThrowError() {
        let givenDict: [String: Any] = [
            "region": String.random
        ]

        XCTAssertThrowsError(try MessagingInAppConfigBuilder.build(from: givenDict)) { error in
            XCTAssertEqual(error as? MessagingInAppConfigBuilderError, MessagingInAppConfigBuilderError.missingSiteId)
        }
    }

    func test_mapInitializationWithIncorrectRegionType_expectDefaultValue() {
        let givenSiteId = String.random
        let givenDict: [String: Any] = [
            "siteId": givenSiteId,
            "region": Region.US
        ]

        let config = try? MessagingInAppConfigBuilder.build(from: givenDict)

        XCTAssertNotNil(config)
        XCTAssertEqual(config?.siteId, givenSiteId)
        XCTAssertEqual(config?.region, Region.US)
    }

    func test_mapInitializationWithIncorrectRegionValue_expectDefaultValue() {
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
