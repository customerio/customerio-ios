@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class MillisecondsTests: UnitTest {
    // MARK: toSeconds

    func test_toSeconds_given0_expect0() {
        let given: Milliseconds = 0

        XCTAssertEqual(given.toSeconds, 0)
    }

    func test_toSeconds_expectConvertToExpectedValue() {
        let given: Milliseconds = 400
        let expected: TimeInterval = 0.4
        let actual = given.toSeconds

        XCTAssertEqual(expected, actual)
    }
}
