@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class SecondsTest: UnitTest {
    func test_fromDays_given0_expect0Seconds() {
        XCTAssertEqual(Seconds.secondsFromDays(0), 0)
    }

    func test_fromDays_givenNumberOfDays_expectNumberOfSeconds() {
        XCTAssertEqual(Seconds.secondsFromDays(3), 259200.0)
    }
}
