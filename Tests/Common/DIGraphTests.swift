@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class DIGraphTests: UnitTest {
    func testDependencyGraphComplete() {
        diGraph.testDependenciesAbleToResolve() // test will fail if an exception occurs while running this function
    }
}
