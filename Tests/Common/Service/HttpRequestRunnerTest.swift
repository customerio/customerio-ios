@testable import CioInternalCommon
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
        guard let runner = runner, let session = session else { return try XCTSkipIf(true) }

        let endpoint = CIOApiEndpoint.findAccountRegion

        let expectComplete = expectation(description: "Expect to complete")
        let requestParams = HttpRequestParams(
            endpoint: endpoint,
            baseUrls: HttpBaseUrls.getProduction(region: Region.US),
            headers: nil,
            body: nil
        )!

        runner
            .request(
                params: requestParams,
                session: session
            ) { data, response, _ in
                print(response!)
                print(data!.string!)

                expectComplete.fulfill()
            }

        waitForExpectations()
    }
}
