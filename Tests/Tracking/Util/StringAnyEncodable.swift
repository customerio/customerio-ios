@testable import CioTracking
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

class StringAnyEncodableTest: UnitTest {

    func test_stringanyencodable_encodes_properly() {
        let expect = DummyData(boolean: true, numeric: 1, testValue: "foo", dict: ["test": "value"], array: [1, 2, 4])

        let data = ["testValue": "foo", "numeric": 1, "boolean": true, "array": [1,2,4], "dict": ["test": "value"] as [String: Any]] as [String : Any]
        
        let json = StringAnyEncodable(data)
        
        guard let actual = jsonAdapter.toJson(json, encoder: nil) else {
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
