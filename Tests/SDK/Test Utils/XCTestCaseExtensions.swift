import Foundation
import XCTest

extension XCTestCase {
    func waitForExpectations(file _: StaticString = #file, line _: UInt = #line) {
        waitForExpectations(timeout: 0.5, handler: nil)
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
