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
        guard let runner = runner, let session = cioSession else { return try XCTSkipIf(true) }

        let endpoint = CIOApiEndpoint.trackPushMetricsCdp

        let expectComplete = expectation(description: "Expect to complete")
        let requestParams = HttpRequestParams(
            endpoint: endpoint,
            baseUrl: "https://cdp.customer.io/v1/",
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

    func testParallelDownloadFileCreatesUniquePaths() {
        let expectation1 = expectation(description: "Parallel download file 1")
        let expectation2 = expectation(description: "Parallel download file 2")

        // Got URL from: https://picsum.photos/
        // Try to find file with a small file size and from a CDN that the CI can download from.
        let url = URL(string: "https://picsum.photos/200/300.jpg")!
        var path1: URL?
        var path2: URL?

        // Initiate the first download
        runner?.downloadFile(
            url: url,
            fileType: .richPushImage,
            session: publicSession,
            onComplete: { path in
                path1 = path
                expectation1.fulfill()
            }
        )

        // Initiate the second download in parallel
        runner?.downloadFile(
            url: url,
            fileType: .richPushImage,
            session: publicSession,
            onComplete: { path in
                path2 = path
                expectation2.fulfill()
            }
        )

        waitForExpectations()

        XCTAssertNotNil(path1)
        XCTAssertNotNil(path2)

        XCTAssertNotEqual(path1, path2, "Expected unique path for each parallel download")
    }
}
