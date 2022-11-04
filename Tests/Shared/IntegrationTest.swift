@testable import CioTracking
@testable import Common
import Foundation
import XCTest

/**
 Extension of `UnitTest` but performs some tasks that sets the environment for integration tests. Unit test classes should have a predictable environment for easier debugging. Integration tests have more SDK code involved and may require some modification to the test environment before tests run.
 */
open class IntegrationTest: UnitTest {
    public var httpRequestRunnerStub: HttpRequestRunnerStub!

    override open func setUp() {
        super.setUp()

        // Because integration tests try to test in an environment that is as to production as possible, we need to
        // initialize the SDK. This is especially important to have the Tracking module setup.
        CustomerIO.initializeIntegrationTests(siteId: testSiteId, diGraph: diGraph)

        // To prevent any real HTTP requests from being sent, override http request runner for all tests.
        httpRequestRunnerStub = HttpRequestRunnerStub()
        diGraph.override(value: httpRequestRunnerStub, forType: HttpRequestRunner.self)
    }
}
