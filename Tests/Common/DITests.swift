@testable import Common
import Foundation
import SharedTests
import XCTest

class DiCommonTests: XCTestCase {
    func testDependencyGraphComplete() {
        for dependency in DependencyCommon.allCases {
            XCTAssertNotNil(DICommon.shared.inject(dependency),
                            "Dependency: \(dependency) not able to resolve in dependency graph. Maybe you're using the Sourcery template incorrectly or there is a circular dependency in your graph?")
        }
    }
}
