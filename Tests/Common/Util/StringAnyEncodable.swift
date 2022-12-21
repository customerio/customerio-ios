@testable import Common
import Foundation
import SharedTests
import XCTest

struct DummyData: Codable, Equatable {
    let boolean: Bool
    let numeric: Int
    let testValue: String
    let dict: [String: String]
    let array: [Int]

    enum CodingKeys: String, CodingKey {
        case boolean
        case numeric
        case testValue
        case dict
        case array
    }
}

struct Unencodable {
    let data: Any
}

class StringAnyEncodableTest: UnitTest {
    func test_stringanyencodable_handles_unencodable_data() {
        let expect = #"{}"#

        let data = ["fooBar": Unencodable(data: 12345)] as [String: Any]

        let json = StringAnyEncodable(data)

        guard let actual = jsonAdapter.toJson(json) else {
            XCTFail("couldn't encode to JSON")
            return
        }

        XCTAssertEqual(expect, actual.string)
    }

    func test_stringanyencodable_encodes_stringstring() {
        // With backward compatibility of making snake casing configurable
        // and with default value of `disableCustomAttributeSnakeCasing` false i.e
        // SDK will snake case the attributes
        let expect = #"{"foo_bar":"bar"}"#

        let data = ["fooBar": "bar"] as [String: String]

        let json = StringAnyEncodable(data)

        guard let actual = jsonAdapter.toJson(json) else {
            XCTFail("couldn't encode to JSON")
            return
        }

        XCTAssertEqual(expect, actual.string)
    }

    func test_stringanyencodable_encodes_stringdouble() {
        let expect = #"{"foo_bar":1.2}"#

        let data = ["fooBar": 1.2] as [String: Double]

        let json = StringAnyEncodable(data)

        guard let actual = jsonAdapter.toJson(json) else {
            XCTFail("couldn't encode to JSON")
            return
        }

        XCTAssertEqual(expect, actual.string)
    }

    func test_stringanyencodable_encodes_nested_data() {
        let expect = #"{"foo_bar":{"bar":1000}}"#

        let data = ["fooBar": ["bar": 1000] as [String: Int]] as [String: Any]

        let json = StringAnyEncodable(data)

        guard let actual = jsonAdapter.toJson(json) else {
            XCTFail("couldn't encode to JSON")
            return
        }

        XCTAssertEqual(expect, actual.string)
    }

    func test_stringanyencodable_encodes_complex_data() {
        let expect = DummyData(boolean: true, numeric: 1, testValue: "foo", dict: ["test": "value"], array: [1, 2, 4])

        let data = [
            "testValue": "foo",
            "numeric": 1,
            "boolean": true,
            "array": [1, 2, 4],
            "dict": ["test": "value"] as [String: Any]
        ] as [String: Any]

        let json = StringAnyEncodable(data)

        guard let actual = jsonAdapter.toJson(json) else {
            XCTFail("couldn't encode to JSON")
            return
        }

        guard let result: DummyData = jsonAdapter.fromJson(actual) else {
            XCTFail("data did not decoded to a DummyData object")
            return
        }

        XCTAssertEqual(expect, result)
    }
}
