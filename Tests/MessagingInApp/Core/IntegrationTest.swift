@testable import CioInternalCommon
@testable import CioMessagingInApp
import Foundation
@testable import SharedTests
import XCTest

/// Extension of `UnitTest` but performs some tasks that sets the environment for integration tests.
/// Unit test classes should have a predictable environment for easier debugging. Integration tests
/// have more SDK code involved and may require some modification to the test environment before tests run.
open class IntegrationTest: UnitTest {
    // Use minimal mocks/stubs in integration tests to closely match production behavior.

    // Mock HTTP requests to Gist backend services.
    let gistQueueNetworkMock = GistQueueNetworkMock()

    override open func setUp() {
        super.setUp()

        diGraphShared.override(value: gistQueueNetworkMock, forType: GistQueueNetwork.self)
    }

    override open func initializeSDKComponents() -> MessagingInAppInstance? {
        // Initialize and configure MessagingPush for testing to closely resemble actual app setup
        MessagingInApp.setUpSharedInstanceForIntegrationTest(diGraphShared: diGraphShared, config: messagingInAppConfigOptions)

        return MessagingInApp.shared
    }

    func setupHttpResponse(code: Int, body: Data) {
        gistQueueNetworkMock.requestClosure = { _, _, completionHandler in
            let response = HTTPURLResponse(url: URL(string: "https://test.com")!, statusCode: code, httpVersion: nil, headerFields: nil)!

            completionHandler(.success((body, response)))
        }
    }
}
