import Foundation
import XCTest

extension XCTest {
    /// Asserts that the actual dictionary matches the expected dictionary, with type-specific comparisons. Assumes `String` as the default type for values unless explicitly specified.
    func XCTAssertMatches(
        _ actual: [String: Any]?,
        _ expected: [String: Any],
        withTypeMap typeMap: [[String]: Any.Type] = [:],
        defaultValueType: Any.Type? = String.self,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let actual = actual else {
            XCTFail("actual dictionary is nil, expected: \(expected)", file: file, line: line)
            return
        }

        guard Set(expected.keys) == Set(actual.keys) else {
            XCTFail("key mismatch - expected keys: \(expected.keys), actual keys: \(actual.keys)", file: file, line: line)
            return
        }

        // transforms `typeMap` from an array of keys to a simpler dict with single string keys mapped to their respective types
        let simplifiedTypeMap: [String: Any.Type] = typeMap.reduce(into: [:]) { result, pair in
            pair.key.forEach { result[$0] = pair.value }
        }

        func assertEqual<T: Equatable>(_ expectedValue: Any, actualValue: Any?, type _: T.Type, key: String, file: StaticString = #file, line: UInt = #line) {
            guard let expectedTypedValue = expectedValue as? T else {
                let expectedType = String(describing: T.self)
                let actualType = String(describing: type(of: expectedValue))
                XCTFail("expected value for key '\(key)' to be of type '\(expectedType)', but found type '\(actualType)' with value '\(expectedValue)'", file: file, line: line)
                return
            }

            XCTAssertEqual(expectedTypedValue, actualValue as? T, "mismatch for key '\(key)': expected '\(expectedValue)', but found '\(actualValue ?? "nil")'", file: file, line: line)
        }

        for (key, expectedValue) in expected {
            guard let actualValue = actual[key], let type = simplifiedTypeMap[key] ?? defaultValueType else {
                XCTFail("typeMap does not contain a type for key '\(key)'", file: file, line: line)
                continue
            }

            switch type {
            case is Bool.Type:
                assertEqual(expectedValue, actualValue: actualValue, type: Bool.self, key: key, file: file, line: line)
            case is Int.Type:
                assertEqual(expectedValue, actualValue: actualValue, type: Int.self, key: key, file: file, line: line)
            case is String.Type:
                assertEqual(expectedValue, actualValue: actualValue, type: String.self, key: key, file: file, line: line)
            default:
                XCTFail("unsupported type for key '\(key)'", file: file, line: line)
            }
        }
    }
}
