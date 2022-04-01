@testable import CioTracking
@testable import Common
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
    public var customerIO: CustomerIO?
    public var deviceInfoMock = DeviceInfoMock()
    public var session: URLSession?

    override open func setUp() {
        super.setUp()

        /**
         We don't want to run these tests on a CI server (flaky!) so, only populate the runner if
         we see environment variables set in XCode.
         */
        if let siteId = getEnvironmentVariable("SITE_ID"), let apiKey = getEnvironmentVariable("API_KEY") {
            runner = UrlRequestHttpRequestRunner()
            customerIO = CustomerIO(siteId: siteId, apiKey: apiKey, region: Region.US)
            session = CIOHttpClient.getSession(siteId: siteId, apiKey: apiKey, deviceInfo: deviceInfoMock)
        }
    }

    override open func tearDown() {
        runner = nil
        /// assert there isn't a memory leak and the runner can be deconstructed.
        XCTAssertNil(runner)

        super.tearDown()
    }

    override open func waitForExpectations(file _: StaticString = #file, line _: UInt = #line) {
        waitForExpectations(5.0)
    }
}
