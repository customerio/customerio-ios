@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class HttpEndpointTest: UnitTest {
    private let defaultEndpoint = CIOApiEndpoint.findAccountRegion
    private var httpBaseUrls: HttpBaseUrls!

    private let defaultHost = "https://customer.io"

    override func setUp() {
        super.setUp()

        setHttpBaseUrls(trackingApi: defaultHost)
    }

    private func setHttpBaseUrls(trackingApi: String) {
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
        let actual = CIOApiEndpoint.identifyCustomer(identifier: "-._~:/|?#[]@!$&'()*+,;=%").getUrlString(baseUrls: httpBaseUrls)

        let expected = "\(defaultHost)/api/v1/customers/-._~:/%7C%3F%23%5B%5D@!$&\'()*+,;=%25"

        XCTAssertEqual(actual, expected)
    }

    func test_getUrl_givenUnencodedPathWithSpecialCharacter_expectReceiveAURL() {
        let identifierWithSpecialChar = "social-login|1234567890abcde"
        let endpoint = CIOApiEndpoint.identifyCustomer(identifier: identifierWithSpecialChar)

        XCTAssertNotNil(endpoint.getUrl(baseUrls: httpBaseUrls), "Expected valid URL but got nil. Ensure path is encoded correctly.")
    }
}
