@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class PushMetricTest: UnitTest {
    func test_metric_givenLowercasedString_expectMetric() {
        let givenDeliveredMetric = Metric.delivered
        let expectedDeliveredMetric = Metric.getEvent(from: "delivered")

        XCTAssertEqual(givenDeliveredMetric, expectedDeliveredMetric)
    }

    func test_metric_givenUppercasedString_expectMetric() {
        let givenOpeneMetric = Metric.opened
        let expectedOpenedMetric = Metric.getEvent(from: "OPENED")

        XCTAssertEqual(givenOpeneMetric, expectedOpenedMetric)
    }

    func test_metric_givenRawString_expectMetric() {
        let givenOpeneMetric = Metric.opened
        let expectedOpenedMetric = Metric.getEvent(from: Metric.opened.rawValue)

        XCTAssertEqual(givenOpeneMetric, expectedOpenedMetric)
    }
}
