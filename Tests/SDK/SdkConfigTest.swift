@testable import CIO
import XCTest

class SdkConfigTest: XCTestCase {
    func test_region_expectGetRegionFromCode() {
        let givenRegion = Region.EU
        let givenRegionCode = givenRegion.code

        let config = SdkConfig(siteId: String.random, apiKey: String.random, regionCode: givenRegionCode)

        let actual = config.region

        XCTAssertEqual(actual, givenRegion)
    }
}
