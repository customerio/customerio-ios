@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class HttpRequestErrorTest: UnitTest {
    func test_expectLocalizedDescrionSameAsDescription() {
        let givenError = HttpRequestError.noRequestMade(nil)

        XCTAssertEqual(givenError.description, givenError.localizedDescription)
    }
}
