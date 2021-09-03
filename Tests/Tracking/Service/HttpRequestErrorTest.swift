@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class HttpRequestErrorTest: UnitTest {
    func test_expectLocalizedDescrionSameAsDescription() {
        let givenError = HttpRequestError.noResponse(nil)

        XCTAssertEqual(givenError.description, givenError.localizedDescription)
    }
}
