@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class DIGraphTests: IntegrationTest {
    func testDependencyGraphComplete() {
        diGraph.testDependenciesAbleToResolve() // test will fail if an exception occurs while running this function
    }
}
