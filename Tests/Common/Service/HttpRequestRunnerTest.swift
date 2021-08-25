@testable import Common
import Foundation
import SharedTests
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

/**
 Test that performs a real HTTP request to Customer.io API. This is a convenient way to test the
 networking layer of the SDK.

 These tests are meant to run on your local machine, not CI server.
 */
class HttpRequestRunnerTest: HttpTest {
    func test_getAccountRegion() throws {
        guard let runner = runner else { return try XCTSkipIf(true) }

        let endpoint = HttpEndpoint.findAccountRegion

        let expectComplete = expectation(description: "Expect to complete")
        let requestParams = HttpRequestParams(endpoint: endpoint, headers: nil, body: nil)
        runner
            .request(requestParams,
                     httpBaseUrls: HttpBaseUrls.getProduction(region: Region.US)) { data, response, error in
                print(response!)
                print(data!.string!)

                expectComplete.fulfill()
            }

        waitForExpectations()
    }
}
