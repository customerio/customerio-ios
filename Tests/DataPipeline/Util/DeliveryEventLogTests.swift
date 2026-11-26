@testable import CioAnalytics
@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

/// A delivery metric from the Notification Service Extension is a live push metric. The diagnostics log names it
/// for what it is, not as a migration replay.
class DeliveryEventLogTests: IntegrationTest {
    private let lines = Synchronized<[String]>([])

    override func tearDown() {
        DataPipelinesDiagnostics.setTestSink(nil)
        super.tearDown()
    }

    func test_trackDeliveryEvent_givenLogOn_expectPushDeliveryInputAndNoMigrationInput() throws {
        let implementation = try XCTUnwrap(DataPipeline.shared.implementation as? DataPipelineImplementation)
        DataPipelinesDiagnostics.setTestSink { [lines] line in lines.mutating { $0.append(line) } }

        implementation.trackDeliveryEvent(token: String.random, event: "delivered", deliveryId: "delivery-1", timestamp: "2026-11-26T10:00:00Z")

        let inputLines = lines.wrappedValue.filter { $0.contains("io=in") }
        XCTAssertEqual(inputLines.count, 1)
        XCTAssertTrue(inputLines.first?.contains("ev=push.delivery") == true)
        XCTAssertFalse(lines.wrappedValue.contains { $0.contains("migration.metric") })
    }
}
