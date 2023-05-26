@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class HttpRequestParamsTest: UnitTest {
    func test_init_givenCIOApiEndpoint_expectGetObject() {
        XCTAssertNotNil(HttpRequestParams(
            endpoint: .identifyCustomer(identifier: .random),
            baseUrls: HttpBaseUrls.getProduction(region: .US),
            headers: nil,
            body: "".data!
        ))
    }
}
