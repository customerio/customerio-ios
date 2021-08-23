@testable import Common
import Foundation
import SharedTests
import XCTest

class SdkConfigTest: UnitTest {
    func test_httpBaseUrl_givenUrls_expectGetCorrectlyMappedValues() {
        let givenTrackingUrl = String.random
        let expected = HttpBaseUrls(trackingApi: givenTrackingUrl)

        let actual = SdkConfig(trackingApiUrl: givenTrackingUrl).httpBaseUrls

        XCTAssertEqual(actual, expected)
    }
}
