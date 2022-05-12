import CioMessagingPush
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

        // Integration tests have a high chance of throwing an exception if the SDK has not been initialized because the SDK assumes that if certain classes in the SDK are executing, the SDK has already been initialized. Therefore, to prevent these errors from occurring, initialize the SDK with random credentials.
        CustomerIO.initialize(siteId: testSiteId, apiKey: String.random)

        // To prevent any real HTTP requests from being sent, override http request runner for all tests.
        httpRequestRunnerStub = HttpRequestRunnerStub()
        diGraph.override(.httpRequestRunner, value: httpRequestRunnerStub, forType: HttpRequestRunner.self)
    }
}
