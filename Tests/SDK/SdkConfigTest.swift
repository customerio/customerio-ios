@testable import CIO
import Foundation
import XCTest

class SdkConfigTest: UnitTest {
    func test_httpBaseUrl_givenUrls_expectGetCorrectlyMappedValues() {
        let givenTrackingUrl = String.random
        let expected = HttpBaseUrls(trackingApi: givenTrackingUrl)

        let actual = SdkConfig(trackingApiUrl: givenTrackingUrl).httpBaseUrls

        XCTAssertEqual(actual, expected)
    }
}
