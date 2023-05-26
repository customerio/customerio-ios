@testable import CioInternalCommon
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
        let expected: CioLogLevel? = nil
        let actual = CioLogLevel.getLogLevel(for: "debuggable")

        XCTAssertEqual(expected, actual)
    }

    func test_LogMappingForKeys() {
        XCTAssertEqual(CioLogLevel.getLogLevel(for: "debug"), CioLogLevel.debug)
        XCTAssertEqual(CioLogLevel.getLogLevel(for: "none"), CioLogLevel.none)
        XCTAssertEqual(CioLogLevel.getLogLevel(for: "error"), CioLogLevel.error)
        XCTAssertEqual(CioLogLevel.getLogLevel(for: "info"), CioLogLevel.info)
    }
}
