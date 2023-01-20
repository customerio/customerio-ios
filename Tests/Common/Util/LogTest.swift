@testable import Common
import Foundation
import SharedTests
import XCTest

class LogTest: UnitTest {
    func test_getLogLevel_givenAllStringValues_expectLogLevel() {
        for logLevelCase in CioLogLevel.allCases {
            let givenString = logLevelCase.rawValue
            let expected = logLevelCase
            let actual = CioLogLevel.getLogLevel(for: givenString)
            XCTAssertEqual(expected, actual)
        }
    }

    func test_loglevel_givenIncorrectString_expectLogLevel() {
        let givenLogLevelError: CioLogLevel? = nil
        let expectedLogLevelError = CioLogLevel.getLogLevel(for: "debuggable")

        XCTAssertEqual(givenLogLevelError, expectedLogLevelError)
    }
}
