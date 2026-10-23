@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import Foundation
import SharedTests
import Testing

/// An identity change the producer completed must survive the process that saw it. Each "process"
/// is a fresh context store, tracker, dwell coordinator and geofence store over the same files;
/// the old objects are released, so their notifications stop, and nothing cleans up in between.
@Suite("GeofenceDwellIdentityRestart", .serialized)
@MainActor
struct GeofenceDwellIdentityRestartTests {
    private static let fence = Geofence(
        id: "fence", latitude: 1, longitude: 2, radius: 150, name: "fence",
        transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1),
        vertices: [
            LocationData(latitude: 0.999, longitude: 1.999),
            LocationData(latitude: 0.999, longitude: 2.001),
            LocationData(latitude: 1.001, longitude: 2.001),
            LocationData(latitude: 1.001, longitude: 1.999)
        ],
        dwellThresholdSeconds: 600
    )

    /// B then A identified, then the process dies before any cleanup removes A's visit. The next
    /// process must not resume it: it spans B. A fresh A stay starts and qualifies on its own.
    @Test
    func identityChangedThenProcessDied_expectTheOldVisitRefusedAndANewStayQualifies() async throws {
        let files = Files()
        var process = await Process(files: files)
        await process.dwell.handleBoundary(geofence: Self.fence, transition: .enter, occurredAt: files.clock.wall)
        let old = try #require(await process.storage.getDwellVisit(geofenceId: Self.fence.id))
        files.clock.advance(600)
        process.contextStore.setUserId("user-b")
        process.contextStore.setUserId("user-a")
        process.dwell.cancelEvidence(for: Self.fence.id)

        process = await Process(files: files)
        await process.dwell.recordInsideEvidence(geofence: Self.fence, at: files.clock.wall, source: "location_evidence")

        #expect(await process.dwellRows().isEmpty)
        #expect(await process.storage.getDwellVisit(geofenceId: Self.fence.id)?.visitId != old.visitId)

        files.clock.advance(600)
        await process.dwell.recordInsideEvidence(geofence: Self.fence, at: files.clock.wall, source: "location_evidence")
        let rows = await process.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId != old.visitId)
        process.dwell.cancelEvidence(for: Self.fence.id)
    }

    /// Control: a restart with no identity change — the same user written again — resumes the
    /// visit, which qualifies with its entry and duration.
    @Test
    func restartWithoutAnIdentityChange_expectTheVisitResumesAndQualifies() async throws {
        let files = Files()
        var process = await Process(files: files)
        let enteredAt = files.clock.wall
        await process.dwell.handleBoundary(geofence: Self.fence, transition: .enter, occurredAt: enteredAt)
        let visit = try #require(await process.storage.getDwellVisit(geofenceId: Self.fence.id))
        files.clock.advance(600)
        process.contextStore.setUserId("user-a")
        process.dwell.cancelEvidence(for: Self.fence.id)

        process = await Process(files: files)
        await process.dwell.recordInsideEvidence(geofence: Self.fence, at: files.clock.wall, source: "location_evidence")

        let rows = await process.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId == visit.visitId)
        #expect(rows[0].enteredAt == enteredAt)
        #expect(rows[0].dwellDurationSeconds == 600)
        process.dwell.cancelEvidence(for: Self.fence.id)
    }

    /// Control: a long same-boot stay with no change at all, confirmed by a late fresh fix after a
    /// restart, still qualifies: no time cutoff.
    @Test
    func longStayConfirmedLateAfterARestart_expectItQualifies() async throws {
        let files = Files()
        var process = await Process(files: files)
        await process.dwell.handleBoundary(geofence: Self.fence, transition: .enter, occurredAt: files.clock.wall)
        process.dwell.cancelEvidence(for: Self.fence.id)
        files.clock.advance(12 * 3600)

        process = await Process(files: files)
        await process.dwell.recordInsideEvidence(geofence: Self.fence, at: files.clock.wall, source: "location_evidence")

        #expect(await process.dwellRows().count == 1)
        process.dwell.cancelEvidence(for: Self.fence.id)
    }

    /// The context record is lost — deleted, or no longer decodable — while the geofence state
    /// survives. The same user identified again reaches the same identity version; the old visit
    /// must still not resume, since nothing proves the identity held throughout. A fresh stay
    /// qualifies on its own.
    @Test(arguments: [false, true])
    func contextRecordLostThenSameUserReidentified_expectTheOldVisitRefused(corrupted: Bool) async throws {
        let files = Files()
        var process = await Process(files: files)
        await process.dwell.handleBoundary(geofence: Self.fence, transition: .enter, occurredAt: files.clock.wall)
        let old = try #require(await process.storage.getDwellVisit(geofenceId: Self.fence.id))
        files.clock.advance(600)
        process.dwell.cancelEvidence(for: Self.fence.id)
        let record = files.contextDirectory.appendingPathComponent("delivery_context.json")
        if corrupted {
            try Data("{\"userId\": 42".utf8).write(to: record)
        } else {
            try FileManager.default.removeItem(at: record)
        }

        process = await Process(files: files)
        // As DataPipeline does at launch for the identified profile.
        process.contextStore.setUserId("user-a")
        await process.dwell.recordInsideEvidence(geofence: Self.fence, at: files.clock.wall, source: "location_evidence")

        #expect(await process.dwellRows().isEmpty)
        #expect(await process.storage.getDwellVisit(geofenceId: Self.fence.id)?.visitId != old.visitId)
        files.clock.advance(600)
        await process.dwell.recordInsideEvidence(geofence: Self.fence, at: files.clock.wall, source: "location_evidence")
        let rows = await process.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId != old.visitId)
        process.dwell.cancelEvidence(for: Self.fence.id)
    }

    /// B then A identified while the context store cannot write, then the process dies. The old
    /// record still names A at the old version; the next process must not resume A's visit from it.
    @Test
    func identityWriteFailedThenProcessDied_expectTheOldVisitRefused() async throws {
        let files = Files()
        var process = await Process(files: files)
        await process.dwell.handleBoundary(geofence: Self.fence, transition: .enter, occurredAt: files.clock.wall)
        let old = try #require(await process.storage.getDwellVisit(geofenceId: Self.fence.id))
        files.clock.advance(600)
        process.dwell.cancelEvidence(for: Self.fence.id)

        files.failContextWrites.wrappedValue = true
        process.contextStore.setUserId("user-b")
        process.contextStore.setUserId("user-a")
        #expect(process.dwell.continuityHolds(for: old, geofenceId: Self.fence.id) == false)
        files.failContextWrites.wrappedValue = false

        process = await Process(files: files)
        process.contextStore.setUserId("user-a")
        await process.dwell.recordInsideEvidence(geofence: Self.fence, at: files.clock.wall, source: "location_evidence")

        #expect(await process.dwellRows().isEmpty)
        #expect(await process.storage.getDwellVisit(geofenceId: Self.fence.id)?.visitId != old.visitId)
        process.dwell.cancelEvidence(for: Self.fence.id)
    }

    // MARK: - Files and processes

    /// What survives a process: the files, and the device's clock.
    @MainActor
    private final class Files {
        let contextDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let geofenceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let clock = ManualGeofenceClock()
        var seeded = false
        /// Fails every context-store write while set: storage that cannot be written.
        let failContextWrites = Synchronized(false)
    }

    /// What a process builds at launch from those files.
    @MainActor
    private struct Process {
        let contextStore: BackgroundDeliveryContextStore
        let tracker: GeofenceIdentityTracker
        let storage: GeofenceStorage
        let outbox: PendingGeofenceMetricStore
        let dwell: GeofenceDwellCoordinator

        init(files: Files) async {
            let failContextWrites = files.failContextWrites
            self.contextStore = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: files.contextDirectory) { data, url in
                if failContextWrites.wrappedValue { throw CocoaError(.fileWriteNoPermission) }
                try data.write(to: url, options: .atomic)
            }
            self.storage = GeofenceStorage(fileManager: .default, directoryURL: files.geofenceDirectory)
            if !files.seeded {
                files.seeded = true
                contextStore.setUserId("user-a")
                await storage.setCachedGeofences([GeofenceDwellIdentityRestartTests.fence])
                await storage.recordRegistration(
                    center: LocationData(latitude: 1, longitude: 2), businessIds: [GeofenceDwellIdentityRestartTests.fence.id]
                )
            }
            self.tracker = GeofenceIdentityTracker(contextStore: contextStore)
            self.outbox = PendingGeofenceMetricStore(
                logger: LoggerMock(), directoryURL: files.geofenceDirectory.appendingPathComponent("outbox")
            )
            // Delivery fails, so every row stays in the outbox to be read.
            let delivery = GeofenceDeliveryTrackerMock()
            delivery.trackMetricClosure = { _, _, onComplete in onComplete(.failure(.transport)) }
            let dateUtil = DateUtilStub()
            dateUtil.givenNow = files.clock.wall
            let eventTracker = GeofenceEventTracker(
                storage: storage, pendingStore: outbox, deliveryTracker: delivery, contextStore: contextStore,
                eventBusHandler: EventBusHandlerMock(), dateUtil: dateUtil, logger: LoggerMock()
            )
            self.dwell = GeofenceDwellCoordinator(
                storage: storage, transitionEmitter: eventTracker, contextStore: contextStore, logger: LoggerMock(),
                notificationCenter: NotificationCenter(), freshFixProvider: { nil }, evidenceRetryDelay: 3600,
                clock: files.clock, identityTracker: tracker
            )
        }

        func dwellRows() async -> [PendingGeofenceMetric] {
            await outbox.rows().filter { $0.transition == .dwell }
        }
    }
}
