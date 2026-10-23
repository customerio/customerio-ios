@testable import CioLocationGeofence
import Foundation
import Testing

@Suite("Dwell diagnostic shortfall")
struct DwellDiagnosticShortfallTests {
    @Test
    func append_givenOldAndShortfallRecords_thenBothSurviveRealJournalRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = DwellDiagnosticJournal.fileURL(in: root)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let input: [String: Any] = [
            "version": 1, "provider": "core_location", "records": [
                ["event": "dwellRejected", "atUptime": 10, "reason": "belowThreshold", "thresholdShortfall": 3.4],
                ["event": "deadlineReached", "atUptime": 11]
            ]
        ]
        try JSONSerialization.data(withJSONObject: input).write(to: file)
        let journal = DwellDiagnosticJournal(directory: root, isEnabled: { true })
        let decoded = try #require(await journal.snapshot())
        try #require(decoded.count == 2, "legacy v1 records without the optional field remain readable")

        #expect(await journal.append(decoded[0]))

        let output = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let rows = try #require(output["records"] as? [[String: Any]])
        #expect(rows.count == 3)
        let newest = try #require(rows.last)
        let shortfall = try #require(newest["thresholdShortfall"] as? Double)
        #expect(abs(shortfall - 3.4) < 0.001)
        #expect(rows[1]["thresholdShortfall"] == nil)
    }
}
