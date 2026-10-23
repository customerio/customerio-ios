@testable import CioLocationGeofence
@testable import CioInternalCommon
import Foundation
import Testing

@Suite("Dwell diagnostic recorder")
@MainActor
struct DwellDiagnosticRecorderTests {
    @Test
    func make_whenIdentityChangedBeforeCoordinatorExists_thenOldDiskHistoryIsErasedAndCurrentRecordsSurvive() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: directory.appendingPathComponent("context"))
        context.setUserId("a")
        let tracker = GeofenceIdentityTracker(contextStore: context)
        let journal = DwellDiagnosticJournal(directory: directory, isEnabled: { true })
        let old = DwellDiagnosticRecorder.make(isOptedIn: true, directory: directory, identityProvider: { tracker.currentIdentity })
        #expect(old.record(.deadlineScheduled, fenceId: "a-fence"))
        await old.drain()
        let token = old.token
        context.setUserId("b")
        let current = DwellDiagnosticRecorder.make(isOptedIn: true, directory: directory, identityProvider: { tracker.currentIdentity })
        #expect(!old.record(.fixReceived, token: token, fenceId: "old-answer"))
        #expect(current.record(.wakeRegion, fenceId: "b-fence"))
        current.syncIdentity() // A later coordinator binding must preserve B's earlier resolver record.
        await old.drain()
        await current.drain()
        #expect(await journal.snapshot()?.map(\.fenceId) == ["b-fence"])
        let reopened = DwellDiagnosticRecorder.make(isOptedIn: true, directory: directory, identityProvider: { tracker.currentIdentity })
        await reopened.drain()
        #expect(await journal.snapshot()?.map(\.fenceId) == ["b-fence"])
    }

    @Test
    func record_whenBoundIdentityIsUnknown_thenWritesNothingAndOptOutRemovesOwnerOnlyStorage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = DwellDiagnosticRecorder.make(isOptedIn: true, directory: directory, identityProvider: { nil })
        #expect(!recorder.record(.wakeRegion, fenceId: "unowned"))
        await recorder.drain()
        #expect(!FileManager.default.fileExists(atPath: DwellDiagnosticJournal.storeDirectory(in: directory).path))
        let journal = DwellDiagnosticJournal(directory: directory, isEnabled: { true })
        let owner = try #require(DwellDiagnosticOwner(GeofenceIdentity(userId: "a", version: 1, lineage: "opaque")))
        #expect(await journal.prepareOwner(owner))
        let off = DwellDiagnosticRecorder.make(isOptedIn: false, directory: directory)
        await off.drain()
        #expect(!FileManager.default.fileExists(atPath: DwellDiagnosticJournal.storeDirectory(in: directory).path))
    }

    @Test
    func invalidateAndClear_whenOldGenerationRacesTheReset_thenOnlyTheNewGenerationIsExported() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = DwellDiagnosticJournal(directory: directory, isEnabled: { true })
        let uptime = ManualUptime()
        let recorder = DwellDiagnosticRecorder(journal: journal, isEnabled: true, now: { [uptime] in uptime.value })
        // Construction touches no storage.
        #expect(!FileManager.default.fileExists(atPath: directory.path))

        #expect(recorder.record(.deadlineScheduled, at: 5, fenceId: "persisted"))
        await recorder.drain()
        let written = try #require(await journal.snapshot())
        #expect(written.map(\.fenceId) == ["persisted"])

        // One record still queued when the reset lands, and a token captured before an await spanning it.
        #expect(recorder.record(.fixRequested, at: 6, fenceId: "queued"))
        let staleToken = recorder.token
        recorder.invalidateAndClear()
        #expect(!recorder.record(.fixReceived, at: 7, token: staleToken, fenceId: "late"))

        uptime.value = 8
        #expect(recorder.record(.dwellEmitted, token: recorder.token, fenceId: "new"))
        await recorder.drain()

        // The clear removed what was written before the reset, and ran before the new generation's write.
        let exported = try #require(await journal.snapshot())
        #expect(exported.map(\.fenceId) == ["new"])
        #expect(exported.map(\.atUptime) == [8])
    }
}

/// The uptime the recorder's `now` reads, set by the test.
@MainActor
private final class ManualUptime {
    var value: TimeInterval = 0
}
