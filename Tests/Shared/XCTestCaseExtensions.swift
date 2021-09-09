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
}
