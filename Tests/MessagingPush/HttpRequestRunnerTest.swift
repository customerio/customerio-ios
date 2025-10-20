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
    func test_getAccountRegion() async throws {
        guard let runner = runner, let session = cioSession else { return try XCTSkipIf(true) }

        let endpoint = CIOApiEndpoint.trackPushMetricsCdp

        let requestParams = HttpRequestParams(
            endpoint: endpoint,
            baseUrl: "https://cdp.customer.io/v1/",
            headers: nil,
            body: nil
        )!

        let (data, response) = try await runner.request(
            params: requestParams,
            session: session
        )
        
        print(response)
        print(data.string!)
    }

    func testParallelDownloadFileCreatesUniquePaths() async {
        guard let runner = runner else { return }

        // Got URL from: https://picsum.photos/
        // Try to find file with a small file size and from a CDN that the CI can download from.
        let url = URL(string: "https://picsum.photos/200/300.jpg")!

        // Initiate both downloads in parallel using async let
        async let path1 = runner.downloadFile(
            url: url,
            fileType: .richPushImage,
            session: publicSession
        )
        
        async let path2 = runner.downloadFile(
            url: url,
            fileType: .richPushImage,
            session: publicSession
        )

        // Await both results
        let (result1, result2) = await (path1, path2)

        XCTAssertNotNil(result1)
        XCTAssertNotNil(result2)

        XCTAssertNotEqual(result1, result2, "Expected unique path for each parallel download")
    }
}
