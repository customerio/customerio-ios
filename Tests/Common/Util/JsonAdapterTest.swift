@testable import Common
import Foundation
import SharedTests
import XCTest

class JsonAdapterTest: UnitTest {
    /**
     Swift TimeInterval = seconds

     Value got from getting the current epoch time (seconds since 1970)
     https://www.epochconverter.com/
     */
    private let givenSecondsSince1970: TimeInterval = 1629743524

    func test_snakeCase_givenObjectInCamelCase_expectJsonStringSnakeCase() {
        let given = TestCase(barDate: Date(timeIntervalSince1970: givenSecondsSince1970))
        let expected = #"{"bar_date":1629743524}"#

        let actual = JsonAdapter.toJson(given)!.string!

        XCTAssertEqual(actual, expected)
    }

    func test_snakeCase_givenStringInSnakeCase_expectObjectInCamelCase() {
        let givenString = #"{"bar_date":1629743524}"#
        let expected = TestCase(barDate: Date(timeIntervalSince1970: givenSecondsSince1970))

        let actual: TestCase = JsonAdapter.fromJson(givenString.data)!

        XCTAssertEqual(actual, expected)
    }

    struct TestCase: Codable, Equatable {
        // make sure property name is camelCase
        let barDate: Date
    }

    func test_fromJson_givenNotValidJsonString_expectGetNil() {
        let givenJson = #"{"foo": "111"}"#

        let actual: TestCase? = JsonAdapter.fromJson(givenJson.data)

        XCTAssertNil(actual)
    }
}
