@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class DateExtensionTest: UnitTest {
    // MARK: add

    func test_add_expectGetDate() {
        let given = Date.fromFormat(.hourMinuteSecond, string: "01:55:00")!
        let expected = Date.fromFormat(.hourMinuteSecond, string: "02:05:00")!
        let actual = given.add(10, .minute)

        XCTAssertEqual(actual, expected)
    }

    func test_addMinutes_given0_expectNoChange() {
        let given = Date.fromFormat(.hourMinuteSecond, string: "01:00:00")!
        let expected = given
        let actual = given.add(0, .minute)

        XCTAssertEqual(actual, expected)
    }

    // MARK: subtract

    func test_subtract_expectDate() {
        let given = Date.fromFormat(.hourMinuteSecond, string: "02:05:00")!
        let expected = Date.fromFormat(.hourMinuteSecond, string: "01:55:00")!
        let actual = given.subtract(10, .minute)

        XCTAssertEqual(actual, expected)
    }

    func test_subtract_given0_expectNoChange() {
        let given = Date.fromFormat(.hourMinuteSecond, string: "01:00:00")!
        let expected = given
        let actual = given.subtract(0, .minute)

        XCTAssertEqual(actual, expected)
    }

    // MARK: hasPassed

    func test_hasPassed_givenDateInThePast_expectTrue() {
        XCTAssertTrue(Date().subtract(10, .minute).hasPassed)
    }

    func test_hasPassed_givenDateInFuture_expectFalse() {
        XCTAssertFalse(Date().add(10, .minute).hasPassed)
    }

    // MARK: isOlderThan

    func test_isOlderThan_givenDateThatIsOlder_expectTrue() {
        XCTAssertTrue(Date().subtract(60, .minute).isOlderThan(Date().subtract(10, .minute)))
    }

    func test_isOlderThan_givenDateThatIsNewer_expectFalse() {
        XCTAssertFalse(Date().subtract(10, .minute).isOlderThan(Date().subtract(60, .minute)))
    }
}
