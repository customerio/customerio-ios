@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class CustomerIOErrorTest: UnitTest {
    func test_expectLocalizedDescrionSameAsDescription() {
        let givenError = CustomerIOError.notInitialized

        XCTAssertEqual(givenError.description, givenError.localizedDescription)
    }
}
