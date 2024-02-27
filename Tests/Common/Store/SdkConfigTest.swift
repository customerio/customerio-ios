@testable import CioInternalCommon
import SharedTests
import XCTest

class SdkConfigTest: UnitTest {
    func test_initializeFromDictionaryWithCustomValues_expectCustomValues() {
        let givenDict: [String: Any] = [
            "logLevel": "debug"
        ]

        let config = SdkConfig.Factory.create(from: givenDict)

        XCTAssertEqual(config.logLevel, .debug)
    }

    func test_initializeFromEmptyDictionary_expectDefaultValues() {
        let givenDict: [String: Any] = [:]

        let config = SdkConfig.Factory.create(from: givenDict)

        XCTAssertEqual(config.logLevel, .error)
    }

    func test_initializeFromDictionaryWithIncorrectLogLevelKey_expectDefaultValues() {
        let givenDict: [String: Any] = [
            "logLevelWrong": "info"
        ]

        let config = SdkConfig.Factory.create(from: givenDict)

        XCTAssertEqual(config.logLevel, .error)
    }

    func test_initializeFromDictionaryWithIncorrectLogLevelType_expectDefaultValues() {
        let givenDict: [String: Any] = [
            "logLevel": CioLogLevel.info
        ]

        let config = SdkConfig.Factory.create(from: givenDict)

        XCTAssertEqual(config.logLevel, .error)
    }
}
