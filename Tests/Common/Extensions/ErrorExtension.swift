@testable import Common
import Foundation
import SharedTests
import XCTest

class ErrorExtensionTest: UnitTest {
    func test_localizedDescription_expectGetDescription() {
        let givenError = HttpRequestError.noResponse
        let expected = givenError.description

        let actual = givenError.localizedDescription

        XCTAssertEqual(actual, expected)
    }
}
