@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class HttpEndpointTest: UnitTest {
    private let defaultEndpoint = HttpEndpoint.findAccountRegion
    private var httpBaseUrls: HttpBaseUrls!

    override func setUp() {
        super.setUp()

        setHttpBaseUrls()
    }

    private func setHttpBaseUrls(trackingApi: String = Region.US.productionTrackingUrl) {
        httpBaseUrls = HttpBaseUrls(trackingApi: trackingApi)
    }

    // MARK: getUrlString

    func test_getUrlString_givenEmptyStringBaseUrl_expectEmptyString() {
        setHttpBaseUrls(trackingApi: "")

        let actual = defaultEndpoint.getUrlString(baseUrls: httpBaseUrls)

        XCTAssertEqual(actual, "")
    }

    func test_getUrlString_givenBaseUrlTrailingSlash_expectValidBaseUrl() {
        let expected = "https://customer.io/api/v1/accounts/region"
        setHttpBaseUrls(trackingApi: "https://customer.io/")

        let actual = defaultEndpoint.getUrlString(baseUrls: httpBaseUrls)

        XCTAssertEqual(actual, expected)
    }

    func test_getUrlString_givenBaseUrlNoTrailingSlash_expectValueBaseUrl() {
        let expected = "https://customer.io/api/v1/accounts/region"
        setHttpBaseUrls(trackingApi: "https://customer.io")

        let actual = defaultEndpoint.getUrlString(baseUrls: httpBaseUrls)

        XCTAssertEqual(actual, expected)
    }
}
