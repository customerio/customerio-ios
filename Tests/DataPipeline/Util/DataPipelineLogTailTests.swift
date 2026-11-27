@testable import CioAnalytics
@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class DataPipelineLogTailTests: UnitTest {
    private let lines = Synchronized<[String]>([])

    override func tearDown() {
        DataPipelinesDiagnostics.setTestSink(nil)
        super.tearDown()
    }

    private func captureLines() {
        DataPipelinesDiagnostics.setTestSink { [lines] line in lines.mutating { $0.append(line) } }
    }

    func test_isEnabled_givenNoInfoPlistKeyAndNoTestSink_expectOff() {
        XCTAssertFalse(DataPipelinesDiagnostics.isEnabled)
    }

    func test_encode_givenSeparatorsAndWhitespace_expectPercentEncodedBytes() {
        XCTAssertEqual(DataPipelineLogTail.encode("a b:c%d=e,f|g"), "a%20b%3Ac%25d%3De%2Cf%7Cg")
        XCTAssertEqual(DataPipelineLogTail.encode("tab\tnl\ndel\u{7F}"), "tab%09nl%0Adel%7F")
        XCTAssertEqual(DataPipelineLogTail.encode("nb\u{00A0}sp é"), "nb%C2%A0sp%20é")
        XCTAssertEqual(DataPipelineLogTail.encode(""), "")
    }

    func test_handOff_givenLoggingGateway_expectLineWithOnlyWhatTheCallCarries() {
        captureLines()
        let gateway = LoggingSegmentGateway(analytics: analytics)
        let instance = DataPipelineLogTail.instance

        gateway.track(name: "Clicked", properties: ["name": "a b", "count": 2, "nested": ["x": 1]])

        XCTAssertEqual(lines.wrappedValue, [
            "handed off to Segment || ev=segment.track io=out sdk=\(instance) event=Clicked p.count=2 p.name=a%20b"
        ])
    }

    func test_input_givenHandOffInsideInput_expectBothLinesCarryTheCallId() {
        captureLines()
        DataPipelineLogTail.newProcess()
        let gateway = LoggingSegmentGateway(analytics: analytics)
        let instance = DataPipelineLogTail.instance

        DataPipelineLogTail.input("api.track", [("event", "Clicked")]) {
            DataPipelineLogTail.input("api.screen", [("event", "Nested")]) {
                gateway.track(name: "Clicked")
            }
        }

        XCTAssertEqual(lines.wrappedValue, [
            "SDK input || ev=api.track io=in call=1 event=Clicked",
            "handed off to Segment || ev=segment.track io=out call=1 sdk=\(instance) event=Clicked"
        ])
    }
}
