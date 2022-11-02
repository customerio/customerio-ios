@testable import CioTracking
import Common
import Foundation
import SharedTests
import XCTest

class DIGraphTests: IntegrationTest {
    func testDependencyGraphComplete() {
        let graph = DIGraph(siteId: testSiteId, apiKey: .random, sdkConfig: SdkConfig.Factory.create(region: Region.US))
        graph.testDependenciesAbleToResolve() // test will fail if an exception occurs while running this function
    }
}
