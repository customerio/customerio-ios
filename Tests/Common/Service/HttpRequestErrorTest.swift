@testable import Common
import Foundation
import SharedTests
import XCTest

class HttpRequestErrorTest: UnitTest {
    func test_expectLocalizedDescrionSameAsDescription() {
        let givenError = HttpRequestError.noResponse

        XCTAssertEqual(givenError.description, givenError.localizedDescription)
    }
}
