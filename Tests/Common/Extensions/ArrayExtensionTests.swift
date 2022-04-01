@testable import Common
import Foundation
import SharedTests
import XCTest

class ArrayExtensionTest: UnitTest {
    // MARK: removeFirstOrNil

    func test_removeFirstOrNil_givenEmptyArray_expectNil() {
        var given: [Int] = []

        XCTAssertNil(given.removeFirstOrNil())
        XCTAssertEqual(given, [])
    }

    func test_removeFirstOrNil_expectRemoveFirstAfterCall() {
        var given: [Int] = [1, 2, 3]

        _ = given.removeFirstOrNil()

        XCTAssertEqual(given, [2, 3])
    }

    func test_removeFirstOrNil_expectNilAfterNoMoreItems() {
        var given: [Int] = [1, 2]

        let actual1 = given.removeFirstOrNil()
        let actual2 = given.removeFirstOrNil()
        let actual3 = given.removeFirstOrNil()

        XCTAssertEqual(actual1, 1)
        XCTAssertEqual(actual2, 2)
        XCTAssertNil(actual3)
    }
}
