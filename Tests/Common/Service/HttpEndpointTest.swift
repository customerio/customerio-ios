@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class HttpEndpointTest: UnitTest {
    private let defaultEndpoint = CIOApiEndpoint.findAccountRegion
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

    func test_getUrlString_givenPathWithSpecialCharacters_expectEncodedPath() {
        let identifierWithSpecialChar = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~:/?#[]@!$&'()*+,;=%"
        let endpoint = CIOApiEndpoint.identifyCustomer(identifier: identifierWithSpecialChar)

        let rawPath = "/api/v1/customers/\(identifierWithSpecialChar)"
        let expectedPath = rawPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rawPath

        let expected = "https://customer.io\(expectedPath)"

        setHttpBaseUrls(trackingApi: "https://customer.io")

        let actual = endpoint.getUrlString(baseUrls: httpBaseUrls)

        XCTAssertEqual(actual, expected)
    }

    func test_getUrl_givenUnencodedPathWithSpecialCharacter_expectValidUrl() {
        let identifierWithSpecialChar = "social-login|1234567890abcde"
        let endpoint = CIOApiEndpoint.identifyCustomer(identifier: identifierWithSpecialChar)

        setHttpBaseUrls(trackingApi: "https://customer.io")

        let actualUrl = endpoint.getUrl(baseUrls: httpBaseUrls)

        XCTAssertNotNil(actualUrl, "Expected valid URL but got nil. Ensure path is encoded correctly.")
    }
}
