@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class ErrorExtensionTest: UnitTest {
    func test_localizedDescription_expectGetDescription() {
        let givenError = HttpRequestError.noRequestMade(nil)
        let expected = givenError.description

        let actual = givenError.localizedDescription

        XCTAssertEqual(actual, expected)
    }
}
