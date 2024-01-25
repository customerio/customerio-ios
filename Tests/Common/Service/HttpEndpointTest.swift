@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class HttpEndpointTest: UnitTest {
    private let defaultEndpoint = CIOApiEndpoint.trackPushMetricsCdp

    override func setUp() {
        super.setUp()
    }

    // MARK: getUrlString

    func test_getUrlString_givenEmptyStringBaseUrl_expectEmptyString() {
        let actual = defaultEndpoint.getUrlString(baseUrl: "")

        XCTAssertEqual(actual, "")
    }

    func test_getUrlString_givenBaseUrlTrailingSlash_expectValidBaseUrl() {
        let expected = "https://cdp.customer.io/v1/track"
        let base = "https://cdp.customer.io/v1/"

        let actual = defaultEndpoint.getUrlString(baseUrl: base)

        XCTAssertEqual(actual, expected)
    }

    func test_getUrlString_givenBaseUrlNoTrailingSlash_expectValueBaseUrl() {
        let expected = "https://cdp.customer.io/v1/track"
        let base = "https://cdp.customer.io/v1"

        let actual = defaultEndpoint.getUrlString(baseUrl: base)

        XCTAssertEqual(actual, expected)
    }
}
