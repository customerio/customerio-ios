@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class DeepLinkUtilTest: UnitTest {
    // MARK: init

    func test_init_givenInvalidUrl_expectNil() {
        // TODO: write tests
    }

    func test_init_givenCustomScheme_expectObject() {}

    func test_init_givenHttpsUrl_expectObject() {}

    func test_init_givenUrlWithoutHost_expectNil() {}

    func test_init_givenPath_expectObjectWithPath() {}

    func test_init_givenQueryParams_expectObjectWithQueryParams() {}
}
