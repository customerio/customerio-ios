@testable import CioTracking
import Common
import Foundation
import SharedTests
import XCTest

class DIGraphTests: XCTestCase {
    func testDependencyGraphComplete() {
        let graph = DIGraph.getInstance(siteId: "test")
        graph.testDependenciesAbleToResolve() // test will fail if an exception occurs while running this function
    }
}
