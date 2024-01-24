@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class HttpRequestParamsTest: UnitTest {
    func test_init_givenCIOApiEndpoint_expectGetObject() {
        XCTAssertNotNil(HttpRequestParams(
            endpoint: .trackPushMetricsCdp,
            baseUrl: "https://cdp.customer.io/v1",
            headers: nil,
            body: "".data!
        ))
    }
}
