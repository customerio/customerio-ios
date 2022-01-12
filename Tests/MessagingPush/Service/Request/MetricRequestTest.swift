@testable import CioMessagingPush
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class MetricRequestTest: UnitTest {
    func test_expectSuccessful_decode_encode() {
        let metric = MetricRequest.random

        guard let jsonData = jsonAdapter.toJson(metric, encoder: nil) else {
            return XCTFail()
        }

        guard let _: MetricRequest = jsonAdapter.fromJson(jsonData) else {
            return XCTFail()
        }
    }

    func test_expectJsonStringApiRequires() {
        let given = MetricRequest(deliveryId: "123", event: .opened, deviceToken: "234",
                                  timestamp: Date(timeIntervalSince1970: 1642018466))
        let expectedJson = """
        {"delivery_id":"123","device_id":"234","event":"opened","timestamp":1642018466}
        """

        guard let jsonData = jsonAdapter.toJson(given, encoder: nil), let actualJson = jsonData.string else {
            return XCTFail()
        }

        print(actualJson)

        XCTAssertEqual(expectedJson, actualJson)
    }
}
