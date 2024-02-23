@testable import CioInternalCommon
@testable import CioTracking
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

/**
 Base class to tests that performs a real HTTP request to Customer.io API. This is a convenient way to test the
 networking layer of the SDK. These tests are meant to run on your local machine, not CI server.

 In order to *run* tests on your local machine, follow these setup steps:
 1. In XCode, go to: Edit Scheme > Run
 2. Create 2 environment variables: `SITE_ID` and `API_KEY`. Populate those values with a set
 of test credentials from a Workspace that you control.
 3. Manually run the tests below. Use the XCode debug console to see the log output for debugging.
 */
open class HttpTest: UnitTest {
    public var runner: HttpRequestRunner?
    public var userAgentUtil: UserAgentUtil!
    public var session: URLSession?
    public var publicSession: URLSession = CIOHttpClient.getBasicSession()

    override open func setUp() {
        super.setUp()

        runner = UrlRequestHttpRequestRunner()
        userAgentUtil = diGraph.userAgentUtil

        /*
         We don't want to run these tests on a CI server (flaky!) so, only populate the runner if
         we see environment variables set in XCode.
         */
        if let siteId = getEnvironmentVariable("SITE_ID"), let apiKey = getEnvironmentVariable("API_KEY") {
            session = CIOHttpClient.getCIOApiSession(
                siteId: siteId,
                apiKey: apiKey,
                userAgentHeaderValue: userAgentUtil.getUserAgentHeaderValue()
            )
        }
    }

    func testParallelDownloadFileCreatesUniquePaths() {
        let expectation1 = expectation(description: "Parallel download file 1")
        let expectation2 = expectation(description: "Parallel download file 2")

        let url = URL(string: "https://thumbs.dreamstime.com/b/bee-flower-27533578.jpg")!
        var path1: URL?
        var path2: URL?

        XCTAssertNotNil(runner)

        // Initiate the first download
        runner?.downloadFile(
            url: url,
            fileType: .richPushImage,
            session: publicSession,
            onComplete: { path in
                XCTAssertNotNil(path)
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
                XCTAssertNotNil(path)
                path2 = path
                expectation2.fulfill()
            }
        )

        // Wait for both downloads to complete
        waitForExpectations(timeout: 20.0) { error in
            if let error = error {
                XCTFail("Test failed with error: \(error)")
            }

            // Verify that both paths are not nil and unique
            XCTAssertNotNil(path1, "First path should not be nil")
            XCTAssertNotNil(path2, "Second path should not be nil")
            XCTAssertNotEqual(path1, path2, "Expected unique path for each parallel download")
        }
    }

    override open func tearDown() {
        runner = nil
        // assert there isn't a memory leak and the runner can be deconstructed.
        XCTAssertNil(runner)

        super.tearDown()
    }

    override open func waitForExpectations(file _: StaticString = #file, line _: UInt = #line) {
        waitForExpectations(5.0)
    }
}
