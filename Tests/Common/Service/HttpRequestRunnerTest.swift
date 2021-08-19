@testable import Common
import Foundation
@testable import SharedTests
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

/**
 Test that performs a real HTTP request to Customer.io API. This is a convenient way to test the
 networking layer of the SDK. These tests are meant to run on your local machine, not CI server.

 Setup:
 1. In XCode, go to: Edit Scheme > Run
 2. Create 2 environment variables: `SITE_ID` and `API_KEY`. Populate those values with a set
 of test credentials from a Workspace that you control.
 3. Manually run the tests below. Use the XCode debug console to see the log output for debugging.
 */
class HttpRequestRunnerTest: UnitTest {
    private var runner: HttpRequestRunner?

    override func setUp() {
        super.setUp()

        /**
         We don't want to run these tests on a CI server (flaky!) so, only populte the runner if
         we see environment variables set in XCode.
         */
        if let siteId = getEnvironmentVariable("SITE_ID"), let apiKey = getEnvironmentVariable("API_KEY") {
            runner = UrlRequestHttpRequestRunner(session: CIOHttpClient.getSession(siteId: siteId, apiKey: apiKey))
        }
    }

    func test_getAccountRegion() {
        guard let runner = runner else { return }

        let endpoint = HttpEndpoint.findAccountRegion

        let expectComplete = expectation(description: "Expect to complete")
        let requestParams = RequestParams(method: endpoint.method,
                                          url: endpoint
                                              .getUrl(baseUrls: HttpBaseUrls(trackingApi: Region.US
                                                      .productionTrackingUrl))!,
                                          headers: nil,
                                          body: nil)
        runner.request(requestParams) { data, response, error in
            print(response!)
            print(data!.string!)

            expectComplete.fulfill()
        }

        waitForExpectations()
    }
}
