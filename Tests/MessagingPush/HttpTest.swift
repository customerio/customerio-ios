@testable import CioInternalCommon
@testable import CioMessagingPush
import Foundation
@testable import SharedTests
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

/**
 Base class to tests that performs a real HTTP request to Customer.io API. This is a convenient way to test the
 networking layer of the SDK. These tests are meant to run on your local machine, not CI server.

 In order to *run* tests on your local machine, follow these setup steps:
 1. In XCode, go to: Edit Scheme > Run
 2. Create an environment variables: `WRITE_KEY`. Populate the values with  test credentials from a source that you control.
 3. Manually run the tests below. Use the XCode debug console to see the log output for debugging.
 */
open class HttpTest: UnitTest {
    public var runner: HttpRequestRunner?
    public var deviceInfo: DeviceInfo!
    public var cioSession: URLSession?
    public var session: URLSession?

    override open func setUp() {
        super.setUp()

        deviceInfo = diGraph.deviceInfo

        /*
         We don't want to run these tests on a CI server (flaky!) so, only populate the runner if
         we see environment variables set in XCode.
         */
        if let writeKey = getEnvironmentVariable("WRITE_KEY") {
            runner = UrlRequestHttpRequestRunner()
            cioSession = RichPushHttpClient.getCIOApiSession(
                key: writeKey,
                userAgentHeaderValue: deviceInfo.getUserAgentHeaderValue()
            )
            session = RichPushHttpClient.getBasicSession()
        }
    }

    func testDownloadFileCreatesExpectedFile() {
        if let session = session {
            let expectation = self.expectation(description: "Download file")

            runner?.downloadFile(
                url: URL(string: "https://thumbs.dreamstime.com/b/bee-flower-27533578.jpg")!,
                fileType: .richPushImage,
                session: session,
                onComplete: { path in
                    XCTAssertNotNil(path)
                    expectation.fulfill()
                }
            )

            waitForExpectations()
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
