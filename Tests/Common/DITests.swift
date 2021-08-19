@testable import Common
import Foundation
@testable import SharedTests
import XCTest

class DiTests: XCTestCase {
    func testDependencyGraphComplete() {
        for dependency in Dependency.allCases {
            XCTAssertNotNil(DI.shared.inject(dependency),
                            "Dependency: \(dependency) not able to resolve in dependency graph. Maybe you're using the Sourcery template incorrectly or there is a circular dependency in your graph?")
        }
    }
}
