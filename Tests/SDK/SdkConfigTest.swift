@testable import CIO
import Foundation
import XCTest

class RegionTest: UnitTest {
    func test_trackingUrl_givenUS_expectCorrectUrl() {
        XCTAssertEqual(Region.US.trackingUrl, "https://track.customer.io/api/v1")
    }

    func test_trackingUrl_givenEU_expectCorrectUrl() {
        XCTAssertEqual(Region.EU.trackingUrl, "https://track-eu.customer.io/api/v1")
    }
}
