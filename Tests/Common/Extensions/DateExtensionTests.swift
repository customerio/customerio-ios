@testable import Common
import Foundation
import SharedTests
import XCTest

class DateExtensionTest: UnitTest {
    // MARK: addMinutes

    func test_addMinutes_expectDateInFutureByXMinutes() {
        let given = Date.fromFormat(.hourMinuteSecond, string: "01:55:00")!
        let expected = Date.fromFormat(.hourMinuteSecond, string: "02:05:00")!
        let actual = given.addMinutes(10)

        XCTAssertEqual(actual, expected)
    }

    func test_addMinutes_given0_expectNoChange() {
        let given = Date.fromFormat(.hourMinuteSecond, string: "01:00:00")!
        let expected = given
        let actual = given.addMinutes(0)

        XCTAssertEqual(actual, expected)
    }

    // MARK: minusMinutes

    func test_minusMinutes_expectDateInPastByXMinutes() {
        let given = Date.fromFormat(.hourMinuteSecond, string: "02:05:00")!
        let expected = Date.fromFormat(.hourMinuteSecond, string: "01:55:00")!
        let actual = given.minusMinutes(10)

        XCTAssertEqual(actual, expected)
    }

    func test_minusMinutes_given0_expectNoChange() {
        let given = Date.fromFormat(.hourMinuteSecond, string: "01:00:00")!
        let expected = given
        let actual = given.minusMinutes(0)

        XCTAssertEqual(actual, expected)
    }

    // MARK: hasPassed

    func test_hasPassed_givenDateInThePast_expectTrue() {
        XCTAssertTrue(Date().minusMinutes(10).hasPassed)
    }

    func test_hasPassed_givenDateInFuture_expectFalse() {
        XCTAssertFalse(Date().addMinutes(10).hasPassed)
    }
}
