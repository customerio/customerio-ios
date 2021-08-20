@testable import Common
import Foundation
@testable import SharedTests
@testable import Tracking
import XCTest

class DiTrackingTests: XCTestCase {
    func testDependencyGraphComplete() {
        for dependency in DependencyTracking.allCases {
            XCTAssertNotNil(DITracking.shared.inject(dependency),
                            "Dependency: \(dependency) not able to resolve in dependency graph. Maybe you're using the Sourcery template incorrectly or there is a circular dependency in your graph?")
        }
    }
}
