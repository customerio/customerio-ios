@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class DIGraphTests: UnitTest {
    func testDependencyGraphComplete() {
        diGraphShared.testDependenciesAbleToResolve() // test will fail if an exception occurs while running this function
        diGraph.testDependenciesAbleToResolve() // test will fail if an exception occurs while running this function
    }
}
