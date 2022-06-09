@testable import CioTracking
import Common
import Foundation
import SharedTests
import XCTest

class DIGraphTests: IntegrationTest {
    func testDependencyGraphComplete() {
        let graph = DIGraph.getInstance(siteId: testSiteId)
        graph.testDependenciesAbleToResolve() // test will fail if an exception occurs while running this function
    }
}
