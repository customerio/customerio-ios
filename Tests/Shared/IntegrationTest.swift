@testable import CioTracking
@testable import Common
import Foundation
import XCTest

/**
 Extension of `UnitTest` but performs some tasks that sets the environment for integration tests. Unit test classes should have a predictable environment for easier debugging. Integration tests have more SDK code involved and may require some modification to the test environment before tests run.
 */
open class IntegrationTest: UnitTest {
    public private(set) var httpRequestRunnerStub: HttpRequestRunnerStub!
    public private(set) var deviceInfoStub: DeviceInfoStub!

    // You get access to properties and functions in UnitTest, too!

    public let givenTimestampNow: Int = .init(TimeInterval(1670443977))
    public lazy var givenTimestampDateNow: Date = .init(timeIntervalSince1970: TimeInterval(givenTimestampNow))

    override open func setUp() {
        super.setUp()

        // To prevent any real HTTP requests from being sent, override http request runner for all tests.
        httpRequestRunnerStub = HttpRequestRunnerStub()
        diGraph.override(value: httpRequestRunnerStub, forType: HttpRequestRunner.self)

        dateUtilStub.givenNow = givenTimestampDateNow
        diGraph.override(value: dateUtilStub, forType: DateUtil.self)

        deviceInfoStub = DeviceInfoStub()
        diGraph.override(value: deviceInfoStub, forType: DeviceInfo.self)

        // Because integration tests try to test in an environment that is as to production as possible, we need to
        // initialize the SDK. This is especially important to have the Tracking module setup.
        CustomerIO.initializeIntegrationTests(siteId: testSiteId, diGraph: diGraph)
    }
}
