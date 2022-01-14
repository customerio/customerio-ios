@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class TrackRequestBodyTest: UnitTest {
    func test_screenview_expectJsonStringApiRequires() {
        let attributes = ["logged_in": false]
        let given = TrackRequestBody(type: .screen, name: "Dashboard", data: attributes,
                                     timestamp: Date(timeIntervalSince1970: 1642018466))
        let expectedJson = """
        {"data":{"logged_in":false},"name":"Dashboard","timestamp":1642018466,"type":"screen"}
        """

        guard let jsonData = jsonAdapter.toJson(given, encoder: nil), let actualJson = jsonData.string else {
            return XCTFail()
        }

        print(actualJson)

        XCTAssertEqual(expectedJson, actualJson)
    }
}
