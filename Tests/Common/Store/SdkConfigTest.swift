@testable import CioInternalCommon
import SharedTests
import XCTest

class SdkConfigTest: UnitTest {
    func test_initializeFromDictionaryWithCustomValues_expectCustomValues() {
        let givenDict: [String: Any] = [
            "logLevel": "debug",
            "source": "ReactNative",
            "version": "3.0.1"
        ]

        let config = SdkConfig.Factory.create(from: givenDict)

        XCTAssertEqual(config.logLevel, .debug)
        XCTAssertNotNil(config._sdkWrapperConfig)
        XCTAssertSame(config._sdkWrapperConfig, SdkWrapperConfig(source: SdkWrapperConfig.Source.reactNative, version: "3.0.1"))
    }

    func test_initializeFromEmptyDictionary_expectDefaultValues() {
        let givenDict: [String: Any] = [:]

        let config = SdkConfig.Factory.create(from: givenDict)

        XCTAssertEqual(config.logLevel, .error)
        XCTAssertNil(config._sdkWrapperConfig)
    }

    func test_initializeFromDictionaryWithOnlyLogLevel_expectNoError() {
        let givenDict: [String: Any] = [
            "logLevel": "info"
        ]

        let config = SdkConfig.Factory.create(from: givenDict)

        XCTAssertEqual(config.logLevel, .info)
        XCTAssertNil(config._sdkWrapperConfig)
    }

    func test_initializeFromDictionaryWithIncorrectLogLevelType_expectDefaultValues() {
        let givenDict: [String: Any] = [
            "logLevel": CioLogLevel.info
        ]

        let config = SdkConfig.Factory.create(from: givenDict)

        XCTAssertEqual(config.logLevel, .error)
        XCTAssertNil(config._sdkWrapperConfig)
    }
}

/// Helper methods to assert custom types.
extension SdkConfigTest {
    func XCTAssertSame(_ actual: SdkWrapperConfig?, _ expected: SdkWrapperConfig, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(actual?.source, expected.source, file: file, line: line)
        XCTAssertEqual(actual?.version, expected.version, file: file, line: line)
    }
}
