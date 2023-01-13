@testable import Common
import Foundation
import SharedTests
import XCTest

class CIOExtensionsTest: UnitTest {
    func test_region_givenString_expectRegion() {
        let givenUSRegion = Region.US
        let expectedUSRegion = Region.getRegion(from: "us")

        XCTAssertEqual(givenUSRegion, expectedUSRegion)

        let givenEURegion = Region.EU
        let expectedEURegion = Region.getRegion(from: "EU")

        XCTAssertEqual(givenEURegion, expectedEURegion)
    }

    func test_loglevel_givenString_expectLogLevel() {
        let givenLogLevelNone = CioLogLevel.none
        let expectedLogLevelNone = CioLogLevel.getLogLevel(for: "none")

        XCTAssertEqual(givenLogLevelNone, expectedLogLevelNone)

        let givenLogLevelError = CioLogLevel.error
        let expectedLogLevelError = CioLogLevel.getLogLevel(for: "error")

        XCTAssertEqual(givenLogLevelError, expectedLogLevelError)
    }

    func test_loglevel_givenInt_expectLogLevel() {
        let givenLogLevelNone = CioLogLevel.none
        let expectedLogLevelNone = CioLogLevel.getLogLevel(for: 1)

        XCTAssertEqual(givenLogLevelNone, expectedLogLevelNone)

        let givenLogLevelError = CioLogLevel.error
        let expectedLogLevelError = CioLogLevel.getLogLevel(for: 2)

        XCTAssertEqual(givenLogLevelError, expectedLogLevelError)
    }

    func test_metric_givenString_expectMetric() {
        let givenDeliveredMetric = Metric.delivered
        let expectedDeliveredMetric = Metric.getEvent(from: "delivered")

        XCTAssertEqual(givenDeliveredMetric, expectedDeliveredMetric)

        let givenOpeneMetric = Metric.opened
        let expectedOpenedMetric = Metric.getEvent(from: "OPENED")

        XCTAssertEqual(givenOpeneMetric, expectedOpenedMetric)
    }
}
