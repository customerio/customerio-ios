@testable import CIO
import XCTest

class SdkConfigTest: XCTestCase {
    func test_region_expectGetRegionFromCode() {
        let givenRegion = Region.EU

        let config = SdkConfig(siteId: String.random, apiKey: String.random, region: givenRegion)

        let actual = config.region

        XCTAssertEqual(actual, givenRegion)
    }
}
