@testable import CioLocationGeofence
import Foundation
import Testing

@Suite("Dwell diagnostic journal")
struct DwellDiagnosticJournalTests {
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    @Test
    func append_whenOwnerReopensThenChanges_thenOnlyCurrentIdentityHistorySurvives() async throws {
        defer { removeRoot() }
        let ownerA = try #require(DwellDiagnosticOwner(GeofenceIdentity(userId: "a", version: 1, lineage: "same-lineage")))
        let ownerB = try #require(DwellDiagnosticOwner(GeofenceIdentity(userId: "b", version: 2, lineage: "same-lineage")))
        let ownerAReturned = try #require(DwellDiagnosticOwner(GeofenceIdentity(userId: "a", version: 3, lineage: "same-lineage")))
        let first = try record(1), second = try record(2), third = try record(3), fourth = try record(4)
        #expect(await make(enabled: true).append(first, owner: ownerA))
        #expect(await make(enabled: true).append(second, owner: ownerA))
        #expect(await make(enabled: true).snapshot() == [first, second], "same owner relaunch retains history")
        #expect(await make(enabled: true).append(third, owner: ownerB))
        #expect(await make(enabled: true).snapshot() == [third])
        #expect(await make(enabled: true).append(fourth, owner: ownerAReturned))
        #expect(await make(enabled: true).snapshot() == [fourth], "returning user is a new identity version")
        let bytes = try Data(contentsOf: DwellDiagnosticJournal.fileURL(in: root))
        let exported = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(Set(exported.keys) == ["version", "provider", "records"])
        #expect(!String(decoding: bytes, as: UTF8.self).contains("same-lineage"))
    }

    @Test(arguments: [false, true])
    func append_whenLegacyOrDamagedOwnerHistoryExists_thenReplacesItBeforeBoundAppend(damaged: Bool) async throws {
        defer { removeRoot() }
        let old = try record(1), current = try record(2)
        #expect(await make(enabled: true).append(old))
        if damaged {
            let sidecar = DwellDiagnosticJournal.storeDirectory(in: root).appendingPathComponent("owner-v1.json")
            try Data(repeating: 120, count: DwellDiagnosticJournal.maxOwnerBytes + 1).write(to: sidecar)
        }
        let owner = try #require(DwellDiagnosticOwner(GeofenceIdentity(userId: "private-user", version: 1, lineage: "opaque")))
        #expect(await make(enabled: true).append(current, owner: owner))
        #expect(await make(enabled: true).snapshot() == [current])
        #expect(DwellDiagnosticOwner(GeofenceIdentity(userId: "a", version: 1, lineage: "")) == nil)
        #expect(DwellDiagnosticOwner(GeofenceIdentity(userId: "a", version: 1, lineage: String(repeating: "x", count: 129))) == nil)
    }

    @Test
    func append_whenOptedOut_thenCreatesNothingAndSnapshotIsEmpty() async throws {
        defer { removeRoot() }
        let journal = make(enabled: false)
        let entry = try record(1)
        #expect(await journal.append(entry) == false)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(await journal.snapshot() == [])
    }

    @Test(arguments: zip([3, 0, 1000, nil] as [Int?], [3, 1, 256, 64]))
    func snapshot_whenReopened_thenNewestRecordsWithinClampedCapacityPersist(
        capacity: Int?,
        kept: Int
    ) async throws {
        defer { removeRoot() }
        let writer = make(enabled: true, capacity: capacity)
        let appended = try (0 ..< kept + 2).map { try record(TimeInterval($0)) }
        for entry in appended {
            #expect(await writer.append(entry))
        }
        // A new instance sees only what reached the file.
        #expect(await make(enabled: true, capacity: capacity).snapshot() == Array(appended.suffix(kept)))
    }

    enum Corruption: CaseIterable, Sendable {
        case notJSON, wrongShape, wrongFieldType, futureVersion, oversizedButValid

        var bytes: Data {
            switch self {
            case .notJSON:
                return Data("dwell".utf8)
            case .wrongShape:
                return Data(#"[{"atUptime":1,"event":"dwellEmitted"}]"#.utf8)
            case .wrongFieldType:
                return Data(#"{"provider":"core_location","records":[{"atUptime":"1","event":"x"}],"version":1}"#.utf8)
            case .futureVersion:
                return Data(#"{"provider":"core_location","records":[],"version":2}"#.utf8)
            case .oversizedButValid:
                // JSON the decoder would accept, so only the size bound refuses it.
                let valid = #"{"provider":"core_location","records":[],"version":1}"#
                return Data((valid + String(repeating: " ", count: DwellDiagnosticJournal.maxFileBytes)).utf8)
            }
        }
    }

    @Test(arguments: Corruption.allCases)
    func snapshot_whenStoredBytesAreNotTheJournals_thenNilUntilAnAppendReplacesThem(
        _ corruption: Corruption
    ) async throws {
        defer { removeRoot() }
        let file = DwellDiagnosticJournal.fileURL(in: root)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try corruption.bytes.write(to: file)
        let journal = make(enabled: true)
        #expect(await journal.snapshot() == nil)
        let entry = try record(7)
        #expect(await journal.append(entry))
        #expect(await make(enabled: true).snapshot() == [entry])
    }

    @Test
    func append_whenValuesAreUnboundedOrInvalid_thenFileHoldsOnlyBoundedAllowedFields() async throws {
        defer { removeRoot() }
        #expect(DwellDiagnosticRecord(event: .fixReceived, atUptime: -1) == nil)
        #expect(DwellDiagnosticRecord(event: .fixReceived, atUptime: .nan) == nil)
        for value in [-1, Double.nan, Double.infinity] {
            let invalid = DwellDiagnosticRecord(event: .dwellRejected, atUptime: 42, thresholdShortfall: value)
            #expect(invalid?.thresholdShortfall == nil)
        }
        let clipped = try #require(DwellDiagnosticRecord(
            event: .dwellRejected, atUptime: 42, fenceId: String(repeating: "🏬", count: 200),
            deadlineUptime: .infinity, reason: .staleFix,
            requestedAccuracy: String(repeating: "a", count: 40), returnedAccuracy: -5, fixAge: .nan,
            thresholdShortfall: .nan
        ))
        let full = try #require(DwellDiagnosticRecord(
            event: .fixReceived, atUptime: 43, fenceId: "fence", deadlineUptime: 300,
            requestedAccuracy: "nearestTenMeters", returnedAccuracy: 8.5, fixAge: 1.25, thresholdShortfall: 3.4
        ))
        let journal = make(enabled: true)
        #expect(await journal.append(clipped))
        #expect(await journal.append(full))

        let bytes = try Data(contentsOf: DwellDiagnosticJournal.fileURL(in: root))
        let object = try JSONSerialization.jsonObject(with: bytes)
        let stored = try #require(object as? [String: Any])
        #expect(Set(stored.keys) == ["provider", "records", "version"])
        #expect(stored["provider"] as? String == "core_location")
        let records = try #require(stored["records"] as? [[String: Any]])
        let allowed: Set = [
            "event", "atUptime", "fenceId", "deadlineUptime", "reason",
            "requestedAccuracy", "returnedAccuracy", "fixAge", "thresholdShortfall"
        ]
        #expect(records.count == 2 && records.allSatisfy { Set($0.keys).isSubset(of: allowed) })
        let first = try #require(records.first)
        #expect(Set(first.keys) == ["event", "atUptime", "fenceId", "reason", "requestedAccuracy"])
        #expect(first["fenceId"] as? String == String(repeating: "🏬", count: 128))
        #expect(first["requestedAccuracy"] as? String == String(repeating: "a", count: 32))
        let directory = DwellDiagnosticJournal.storeDirectory(in: root)
        let backup = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(backup.isExcludedFromBackup == true)
        #expect(await make(enabled: true).snapshot() == [clipped, full])
    }

    @Test
    func clear_whenOptedOut_thenRemovesHistoryALaterOptedInReaderWouldSee() async throws {
        defer { removeRoot() }
        let entry = try record(1)
        #expect(await make(enabled: true).append(entry))
        let optedOut = make(enabled: false)
        #expect(await optedOut.clear())
        #expect(!FileManager.default.fileExists(atPath: DwellDiagnosticJournal.storeDirectory(in: root).path))
        #expect(await optedOut.clear())
        #expect(await make(enabled: true).snapshot() == [])
    }

    @Test
    func append_whenCallingTaskIsCancelled_thenWritesNothing() async throws {
        defer { removeRoot() }
        let journal = make(enabled: true)
        let entry = try record(1)
        let persisted = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await journal.append(entry)
        }.value
        #expect(!persisted)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(await journal.append(entry))
    }

    private func make(enabled: Bool, capacity: Int? = nil) -> DwellDiagnosticJournal {
        guard let capacity else { return DwellDiagnosticJournal(directory: root) { enabled } }
        return DwellDiagnosticJournal(directory: root, capacity: capacity) { enabled }
    }

    private func record(_ atUptime: TimeInterval) throws -> DwellDiagnosticRecord {
        try #require(DwellDiagnosticRecord(event: .deadlineReached, atUptime: atUptime, fenceId: "fence"))
    }

    private func removeRoot() {
        try? FileManager.default.removeItem(at: root)
    }
}
