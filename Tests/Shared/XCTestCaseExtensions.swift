import Foundation
import XCTest

public extension XCTestCase {
    func waitForExpectations(_ timeout: Double, file _: StaticString = #file, line _: UInt = #line) {
        waitForExpectations(timeout: timeout, handler: nil)
    }

    func waitForExpectations(
        for expectations: [XCTestExpectation],
        enforceOrder: Bool = false,
        file _: StaticString = #file,
        line _: UInt = #line
    ) {
        wait(for: expectations, timeout: 0.5, enforceOrder: enforceOrder)
    }

    func getEnvironmentVariable(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }

    func XCTAssertEqualEither<T: Equatable>(_ expected: [T], actual: T, file: StaticString = #file,
                                            line: UInt = #line)
    {
        let matches = expected.contains { value in
            value == actual
        }

        if !matches {
            XCTFail("\(actual) does not equal any of: \(expected)", file: file, line: line)
        }
    }

    func XCTAssertMatches(_ actual: String, regex: String, file: StaticString = #file,
                          line: UInt = #line)
    {
        let matches = actual.matches(regex: regex)

        if !matches {
            XCTFail("\(actual) does not match pattern: \(regex)", file: file, line: line)
        }
    }
}
