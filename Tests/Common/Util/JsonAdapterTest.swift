@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class JsonAdapterTest: UnitTest {
    /**
     Swift TimeInterval = seconds

     Value got from getting the current epoch time (seconds since 1970)
     https://www.epochconverter.com/
     */
    private let givenSecondsSince1970: TimeInterval = 1629743524.100

    // MARK: toJson

    func test_toJson_givenObject_expectJsonString() {
        let given = TestCase(barDate: Date(timeIntervalSince1970: givenSecondsSince1970))
        let expected = #"{"bar_date":1629743524}"#

        let actual = jsonAdapter.toJson(given)!.string!

        XCTAssertEqual(actual, expected)
    }

    // MARK: fromJson

    func test_fromJson_givenString_expectGetObject() {
        let givenString = #"{"bar_date":1629743524.100}"#
        let expected = TestCase(barDate: Date(timeIntervalSince1970: givenSecondsSince1970))

        let actual: TestCase = jsonAdapter.fromJson(givenString.data)!

        XCTAssertEqual(actual, expected)
    }

    func test_fromJson_givenInValidJsonString_expectGetNil() {
        let givenJson = #"{"foo": "111"}"#

        let actual: TestCase? = jsonAdapter.fromJson(givenJson.data)

        XCTAssertNil(actual)
    }

    // MARK: fromDictionary

    func test_fromDictionary_givenDictionaryMatchingObject_expectObject() {
        struct Person: Codable, Equatable {
            let firstName: String
        }

        let given = ["firstName": "Dana"]
        let expected = Person(firstName: "Dana")

        let actual: Person = jsonAdapter.fromDictionary(given)!

        XCTAssertEqual(expected, actual)
    }

    func test_fromDictionary_givenDictionaryNotMatchingObject_expectNil() {
        struct Person: Codable, Equatable {
            let firstName: String
        }

        let given = ["lastName": "Dana", "email": "you@you.com"]

        let actual: Person? = jsonAdapter.fromDictionary(given)

        XCTAssertNil(actual)
    }

    func test_fromDictionary_givenDictionaryWithNesting_expectObject() {
        struct Person: Codable, Equatable {
            let name: Name
        }
        struct Name: Codable, Equatable {
            let first: String
            let last: String
        }

        let given = ["name": ["first": "Dana", "last": "Green"]]
        let expected = Person(name: Name(first: "Dana", last: "Green"))

        let actual: Person = jsonAdapter.fromDictionary(given)!

        XCTAssertEqual(expected, actual)
    }

    // MARK: toDictionary

    func test_toDictionary_givenObjectWithNesting_expectDictionary() {
        struct Person: Codable, Equatable {
            let name: Name
        }
        struct Name: Codable, Equatable {
            let first: String
        }

        let given = Person(name: Name(first: "Dana"))
        let expected = ["name": ["first": "Dana"]]

        let actual = jsonAdapter.toDictionary(given) as? [String: [String: String]]

        XCTAssertEqual(expected, actual)
    }

    func test_toDictionary_givenObject_expectDictionary() {
        struct Person: Codable, Equatable {
            let name: String
        }

        let given = Person(name: "Dana")
        let expected = ["name": "Dana"]

        let actual = jsonAdapter.toDictionary(given) as? [String: String]

        XCTAssertEqual(expected, actual)
    }
}

struct TestCase: Codable, Equatable {
    // make sure property name is camelCase
    let barDate: Date

    enum CodingKeys: String, CodingKey {
        case barDate = "bar_date"
    }
}
