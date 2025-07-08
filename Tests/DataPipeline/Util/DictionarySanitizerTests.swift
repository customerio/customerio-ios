@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class DictionarySanitizerTests: UnitTest {
    private var loggerMock = LoggerMock()

    func test_sanitizedForJSON_givenDictionaryWithNaN_expectNaNValuesRemoved() {
        // Given
        let dictionary: [String: Any] = [
            "validKey": "validValue",
            "nanKey": Double.nan,
            "anotherValidKey": 42
        ]

        // When
        let sanitized = dictionary.sanitizedForJSON(logger: loggerMock)

        // Then
        XCTAssertEqual(sanitized.count, 2)
        XCTAssertEqual(sanitized["validKey"] as? String, "validValue")
        XCTAssertEqual(sanitized["anotherValidKey"] as? Int, 42)
        XCTAssertNil(sanitized["nanKey"])

        // Verify logging
        XCTAssertEqual(loggerMock.errorCallsCount, 1)
        XCTAssertEqual(loggerMock.errorReceivedArguments?.message, "Removed unsupported numeric value")
    }

    func test_sanitizedForJSON_givenDictionaryWithInfinity_expectInfinityValuesRemoved() {
        // Given
        let dictionary: [String: Any] = [
            "validKey": "validValue",
            "positiveInfinityKey": Double.infinity,
            "negativeInfinityKey": -Double.infinity,
            "anotherValidKey": 42
        ]

        // When
        let sanitized = dictionary.sanitizedForJSON(logger: loggerMock)

        // Then
        XCTAssertEqual(sanitized.count, 2)
        XCTAssertEqual(sanitized["validKey"] as? String, "validValue")
        XCTAssertEqual(sanitized["anotherValidKey"] as? Int, 42)
        XCTAssertNil(sanitized["positiveInfinityKey"])
        XCTAssertNil(sanitized["negativeInfinityKey"])

        // Verify logging
        XCTAssertEqual(loggerMock.errorCallsCount, 2)
        XCTAssertEqual(loggerMock.errorReceivedArguments?.message, "Removed unsupported numeric value")
    }

    func test_sanitizedForJSON_givenDictionaryWithNestedDictionary_expectNestedNaNAndInfinityValuesRemoved() {
        // Given
        let dictionary: [String: Any] = [
            "validKey": "validValue",
            "nestedDict": [
                "validNestedKey": 123,
                "nanNestedKey": Double.nan,
                "infinityNestedKey": Double.infinity
            ],
            "anotherValidKey": 42
        ]

        // When
        let sanitized = dictionary.sanitizedForJSON(logger: loggerMock)

        // Then
        XCTAssertEqual(sanitized.count, 3)
        XCTAssertEqual(sanitized["validKey"] as? String, "validValue")
        XCTAssertEqual(sanitized["anotherValidKey"] as? Int, 42)

        if let nestedDict = sanitized["nestedDict"] as? [String: Any] {
            XCTAssertEqual(nestedDict.count, 1)
            XCTAssertEqual(nestedDict["validNestedKey"] as? Double, 123)
            XCTAssertNil(nestedDict["nanNestedKey"])
            XCTAssertNil(nestedDict["infinityNestedKey"])
        } else {
            XCTFail("Expected nestedDict to be a dictionary")
        }

        // Verify logging
        XCTAssertGreaterThanOrEqual(loggerMock.errorCallsCount, 2)
        XCTAssertEqual(loggerMock.errorReceivedArguments?.message, "Removed unsupported numeric value")
    }

    func test_sanitizedForJSON_givenDictionaryWithArray_expectArrayItemsWithNaNAndInfinityRemoved() {
        // Given
        let dictionary: [String: Any] = [
            "validKey": "validValue",
            "arrayKey": [1, Double.nan, "valid", Double.infinity, 5],
            "anotherValidKey": 42
        ]

        // When
        let sanitized = dictionary.sanitizedForJSON(logger: loggerMock)

        // Then
        XCTAssertEqual(sanitized.count, 3)
        XCTAssertEqual(sanitized["validKey"] as? String, "validValue")
        XCTAssertEqual(sanitized["anotherValidKey"] as? Int, 42)

        if let array = sanitized["arrayKey"] as? [Any] {
            XCTAssertEqual(array.count, 3)
            XCTAssertEqual(array[0] as? Int, 1)
            XCTAssertEqual(array[1] as? String, "valid")
            XCTAssertEqual(array[2] as? Int, 5)
        } else {
            XCTFail("Expected arrayKey to be an array")
        }

        // Verify logging
        XCTAssertGreaterThanOrEqual(loggerMock.errorCallsCount, 2)
        XCTAssertEqual(loggerMock.errorReceivedArguments?.message, "Removed unsupported numeric value")
    }

    func test_sanitizedForJSON_givenDictionaryWithNestedArrayContainingDictionaries_expectInvalidValuesRemoved() {
        // Given
        let dictionary: [String: Any] = [
            "validKey": "validValue",
            "arrayOfDicts": [
                ["key1": "value1", "key2": Double.nan],
                ["key3": Double.infinity, "key4": 42],
                ["key5": "value5"]
            ],
            "anotherValidKey": 42
        ]

        // When
        let sanitized = dictionary.sanitizedForJSON(logger: loggerMock)

        // Then
        XCTAssertEqual(sanitized.count, 3)
        XCTAssertEqual(sanitized["validKey"] as? String, "validValue")
        XCTAssertEqual(sanitized["anotherValidKey"] as? Int, 42)

        if let arrayOfDicts = sanitized["arrayOfDicts"] as? [Any] {
            XCTAssertEqual(arrayOfDicts.count, 3)

            if let dict1 = arrayOfDicts[0] as? [String: Any] {
                XCTAssertEqual(dict1.count, 1)
                XCTAssertEqual(dict1["key1"] as? String, "value1")
                XCTAssertNil(dict1["key2"])
            } else {
                XCTFail("Expected first item to be a dictionary")
            }

            if let dict2 = arrayOfDicts[1] as? [String: Any] {
                XCTAssertEqual(dict2.count, 1)
                XCTAssertEqual(dict2["key4"] as? Int, 42)
                XCTAssertNil(dict2["key3"])
            } else {
                XCTFail("Expected second item to be a dictionary")
            }

            if let dict3 = arrayOfDicts[2] as? [String: Any] {
                XCTAssertEqual(dict3.count, 1)
                XCTAssertEqual(dict3["key5"] as? String, "value5")
            } else {
                XCTFail("Expected third item to be a dictionary")
            }
        } else {
            XCTFail("Expected arrayOfDicts to be an array")
        }
    }

    func test_sanitizedForJSON_givenDictionaryWithFloatNaNAndInfinity_expectInvalidValuesRemoved() {
        // Given
        let dictionary: [String: Any] = [
            "validKey": "validValue",
            "nanKey": Float.nan,
            "positiveInfinityKey": Float.infinity,
            "negativeInfinityKey": -Float.infinity,
            "anotherValidKey": 42
        ]

        // When
        let sanitized = dictionary.sanitizedForJSON(logger: loggerMock)

        // Then
        XCTAssertEqual(sanitized.count, 2)
        XCTAssertEqual(sanitized["validKey"] as? String, "validValue")
        XCTAssertEqual(sanitized["anotherValidKey"] as? Int, 42)
        XCTAssertNil(sanitized["nanKey"])
        XCTAssertNil(sanitized["positiveInfinityKey"])
        XCTAssertNil(sanitized["negativeInfinityKey"])

        // Verify logging
        XCTAssertEqual(loggerMock.errorCallsCount, 3)
        XCTAssertEqual(loggerMock.errorReceivedArguments?.message, "Removed unsupported numeric value")
    }

    func test_sanitizedForJSON_givenEmptyNestedStructures_expectEmptyStructuresRemoved() {
        // Given
        let dictionary: [String: Any] = [
            "validKey": "validValue",
            "emptyDictAfterSanitization": ["nanKey": Double.nan],
            "arrayWithEmptyDict": [["nanKey": Double.nan]],
            "anotherValidKey": 42
        ]

        // When
        let sanitized = dictionary.sanitizedForJSON(logger: loggerMock)

        // Then
        XCTAssertEqual(sanitized.count, 2)
        XCTAssertEqual(sanitized["validKey"] as? String, "validValue")
        XCTAssertEqual(sanitized["anotherValidKey"] as? Int, 42)
        XCTAssertNil(sanitized["emptyDictAfterSanitization"])
        XCTAssertNil(sanitized["arrayWithEmptyDict"])

        // Verify logging
        XCTAssertGreaterThanOrEqual(loggerMock.errorCallsCount, 1)
        XCTAssertEqual(loggerMock.errorReceivedArguments?.message, "Removed unsupported numeric value")
    }

    func test_sanitizedForJSON_givenValidDictionary_expectNoChanges() {
        // Given
        let dictionary: [String: Any] = [
            "stringKey": "stringValue",
            "intKey": 42,
            "doubleKey": 3.14,
            "boolKey": true,
            "arrayKey": [1, 2, 3],
            "dictKey": ["nestedKey": "nestedValue"]
        ]

        // When
        let sanitized = dictionary.sanitizedForJSON(logger: loggerMock)

        // Then
        XCTAssertEqual(sanitized.count, dictionary.count)
        XCTAssertEqual(sanitized["stringKey"] as? String, "stringValue")
        XCTAssertEqual(sanitized["intKey"] as? Int, 42)
        XCTAssertEqual(sanitized["doubleKey"] as? Double, 3.14)
        XCTAssertEqual(sanitized["boolKey"] as? Bool, true)

        if let array = sanitized["arrayKey"] as? [Int] {
            XCTAssertEqual(array, [1, 2, 3])
        } else {
            XCTFail("Expected arrayKey to be an array of integers")
        }

        if let dict = sanitized["dictKey"] as? [String: String] {
            XCTAssertEqual(dict, ["nestedKey": "nestedValue"])
        } else {
            XCTFail("Expected dictKey to be a dictionary")
        }
    }

    func test_sanitizedForJSON_givenIntegerValues_expectIntegersRemainIntegers() {
        // Given
        let dictionary: [String: Any] = [
            "intValue": 1,
            "anotherIntValue": 42,
            "zeroValue": 0,
            "largeIntValue": 9999999
        ]

        // When
        let sanitized = dictionary.sanitizedForJSON(logger: loggerMock)

        // Then
        XCTAssertEqual(sanitized.count, dictionary.count)

        // Verify that integers remain integers (not converted to Double/Float)
        XCTAssertTrue(sanitized["intValue"] is Int, "Integer should remain an Int type")
        XCTAssertFalse(sanitized["intValue"] is Double, "Integer should not be converted to Double")
        XCTAssertFalse(sanitized["intValue"] is Float, "Integer should not be converted to Float")
        XCTAssertEqual(sanitized["intValue"] as? Int, 1)

        XCTAssertTrue(sanitized["anotherIntValue"] is Int, "Integer should remain an Int type")
        XCTAssertEqual(sanitized["anotherIntValue"] as? Int, 42)

        XCTAssertTrue(sanitized["zeroValue"] is Int, "Zero should remain an Int type")
        XCTAssertEqual(sanitized["zeroValue"] as? Int, 0)

        XCTAssertTrue(sanitized["largeIntValue"] is Int, "Large integer should remain an Int type")
        XCTAssertEqual(sanitized["largeIntValue"] as? Int, 9999999)
    }

    func test_sanitizedForJSON_givenNestedIntegerValues_expectIntegersRemainIntegers() {
        // Given
        let dictionary: [String: Any] = [
            "topLevelInt": 100,
            "nestedDict": [
                "nestedInt": 1,
                "anotherNestedInt": 42
            ],
            "nestedArray": [1, 2, 3, 4, 5]
        ]

        // When
        let sanitized = dictionary.sanitizedForJSON(logger: loggerMock)

        // Then
        XCTAssertEqual(sanitized.count, dictionary.count)

        // Verify top-level integer
        XCTAssertTrue(sanitized["topLevelInt"] is Int, "Top-level integer should remain an Int type")
        XCTAssertEqual(sanitized["topLevelInt"] as? Int, 100)

        // Verify nested dictionary integers
        if let nestedDict = sanitized["nestedDict"] as? [String: Any] {
            XCTAssertTrue(nestedDict["nestedInt"] is Int, "Nested integer should remain an Int type")
            XCTAssertFalse(nestedDict["nestedInt"] is Double, "Nested integer should not be converted to Double")
            XCTAssertEqual(nestedDict["nestedInt"] as? Int, 1)

            XCTAssertTrue(nestedDict["anotherNestedInt"] is Int, "Nested integer should remain an Int type")
            XCTAssertEqual(nestedDict["anotherNestedInt"] as? Int, 42)
        } else {
            XCTFail("Expected nestedDict to be a dictionary")
        }

        // Verify array integers
        if let nestedArray = sanitized["nestedArray"] as? [Any] {
            XCTAssertEqual(nestedArray.count, 5)

            for (index, value) in nestedArray.enumerated() {
                XCTAssertTrue(value is Int, "Array integer at index \(index) should remain an Int type")
                XCTAssertFalse(value is Double, "Array integer at index \(index) should not be converted to Double")
                XCTAssertEqual(value as? Int, index + 1)
            }
        } else {
            XCTFail("Expected nestedArray to be an array")
        }
    }

    func test_sanitizedForJSON_givenDictionaryWithBooleans_expectBooleansPreserved() {
        // Given
        let dictionary: [String: Any] = [
            "trueValue": true,
            "falseValue": false,
            "nestedDict": [
                "nestedTrue": true,
                "nestedFalse": false
            ],
            "mixedArray": [true, 42, "string", false]
        ]

        // When
        let sanitized = dictionary.sanitizedForJSON(logger: loggerMock)

        // Then
        XCTAssertEqual(sanitized.count, dictionary.count)

        // Verify boolean values are preserved
        XCTAssertTrue(sanitized["trueValue"] is Bool, "True value should remain a Bool type")
        XCTAssertEqual(sanitized["trueValue"] as? Bool, true)

        XCTAssertTrue(sanitized["falseValue"] is Bool, "False value should remain a Bool type")
        XCTAssertEqual(sanitized["falseValue"] as? Bool, false)

        // Verify nested dictionary booleans
        if let nestedDict = sanitized["nestedDict"] as? [String: Any] {
            XCTAssertTrue(nestedDict["nestedTrue"] is Bool, "Nested true should remain a Bool type")
            XCTAssertEqual(nestedDict["nestedTrue"] as? Bool, true)

            XCTAssertTrue(nestedDict["nestedFalse"] is Bool, "Nested false should remain a Bool type")
            XCTAssertEqual(nestedDict["nestedFalse"] as? Bool, false)
        } else {
            XCTFail("Expected nestedDict to be a dictionary")
        }

        // Verify array booleans
        if let mixedArray = sanitized["mixedArray"] as? [Any] {
            XCTAssertEqual(mixedArray.count, 4)
            XCTAssertTrue(mixedArray[0] is Bool, "First array element should be a Bool")
            XCTAssertEqual(mixedArray[0] as? Bool, true)
            XCTAssertEqual(mixedArray[1] as? Int, 42)
            XCTAssertEqual(mixedArray[2] as? String, "string")
            XCTAssertTrue(mixedArray[3] is Bool, "Fourth array element should be a Bool")
            XCTAssertEqual(mixedArray[3] as? Bool, false)
        } else {
            XCTFail("Expected mixedArray to be an array")
        }
    }
}
