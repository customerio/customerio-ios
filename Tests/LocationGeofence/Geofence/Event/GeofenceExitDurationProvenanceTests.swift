@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import CoreLocation
import Foundation
import SharedTests
import Testing

/// A completed visit's EXIT duration against the foundation's provenance: the durable identity,
/// legacy visits, unproven candidates, superseding native ENTERs and the first clock reading.
/// Boundaries go through the production resolver, the dwell coordinator, the real tracker and the
/// file outbox; the context store is the real one, written through its setters. Each "process" is
/// a fresh store, tracker, coordinator and resolver over the same files. Delivery fails and a CDP
/// key is set, so every row the tracker writes stays in the outbox to be read.
@Suite("GeofenceExitDurationProvenance", .serialized)
@MainActor
struct GeofenceExitDurationProvenanceTests {
    /// EXIT-only, dwell disabled: its visits exist only to time the EXIT.
    private static let exitOnly = Geofence(
        id: "exit-only", latitude: 0, longitude: 0, radius: 100, name: "exit-only",
        transitionTypes: [.exit], lastUpdated: Date(timeIntervalSince1970: 1)
    )
    /// ENTER, EXIT and a dwell threshold, for the unproven-candidate paths.
    private static let dwellCircle = Geofence(
        id: "dwell-circle", latitude: 0, longitude: 0, radius: 100, name: "dwell-circle",
        transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1),
        dwellThresholdSeconds: 600
    )

    // MARK: - Identity

    /// The user changes away and back through the context store's setter, with no profile event
    /// delivered at all. The EXIT that ends the earlier visit is still delivered, but must not time
    /// a stay that spans another identity. A stay entered after the change is timed.
    @Test
    func userChangedAwayAndBackBeforeAnyProfileEventLeavesTheExitUntimed() async throws {
        let files = Files()
        let process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly)
        let old = try #require(await process.storage.getDwellVisit(geofenceId: Self.exitOnly.id))
        files.advance(300)
        process.contextStore.setUserId("user-b")
        process.contextStore.setUserId("user-a")
        files.advance(300)

        await process.crossing(.exit, Self.exitOnly)

        let untimed = try #require(await process.exitRows().last)
        #expect(untimed.userId == "user-a")
        #expect(untimed.visitId == nil)
        #expect(untimed.enteredAt == nil)
        #expect(untimed.visitDurationSeconds == nil)
        #expect(await process.storage.getDwellVisit(geofenceId: Self.exitOnly.id) == nil)

        files.advance(60)
        let reentry = files.clock.wall
        await process.crossing(.enter, Self.exitOnly)
        files.advance(90)
        await process.crossing(.exit, Self.exitOnly)
        let rows = await process.exitRows()
        try #require(rows.count == 2)
        #expect(rows[1].visitId != old.visitId)
        #expect(rows[1].enteredAt.map { Int($0.timeIntervalSince1970) } == Int(reentry.timeIntervalSince1970))
        #expect(rows[1].visitDurationSeconds == 90)
    }

    /// The profile callback for an earlier B is delivered late — before or after A's new ENTER.
    /// It decides nothing by its timing: A's new visit, recorded under the identity now in force,
    /// keeps its id, its known entry and its duration.
    @Test(arguments: [true, false])
    func lateProfileEventForAnEarlierChangeKeepsTheNewVisitTimed(deliveredBeforeTheEntry: Bool) async throws {
        let files = Files()
        let process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly)
        files.advance(60)
        process.contextStore.setUserId("user-b")
        process.contextStore.setUserId("user-a")
        files.advance(30)
        // What the module's ProfileIdentifiedEvent observer runs.
        if deliveredBeforeTheEntry { await process.dwell.identityChanged() }
        let entry = files.clock.wall
        await process.crossing(.enter, Self.exitOnly)
        let visit = try #require(await process.storage.getDwellVisit(geofenceId: Self.exitOnly.id))
        if !deliveredBeforeTheEntry { await process.dwell.identityChanged() }
        files.advance(120)

        await process.crossing(.exit, Self.exitOnly)

        let row = try #require(await process.exitRows().last)
        #expect(visit.enteredAt == entry)
        #expect(row.visitId == visit.visitId)
        #expect(row.enteredAt.map { Int($0.timeIntervalSince1970) } == Int(entry.timeIntervalSince1970))
        #expect(row.visitDurationSeconds == 120)
    }

    /// An EXIT is still in flight when a re-entry replaces its visit, then the user changes away
    /// and back before that EXIT reads it. The replaced visit spans the change: the EXIT reports
    /// no duration for it, and the re-entry recorded before the change is not timed either. The
    /// first delivery of the EXIT is the one-receiver-later copy the overlap tests use: received
    /// for another user, it records itself before any await, then is dropped.
    @Test
    func identityChangeWhileAnOverlappingExitIsPendingLeavesItUntimed() async throws {
        let files = Files()
        let process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly)
        files.advance(60)
        let exitedAt = files.clock.wall
        await process.crossing(.exit, Self.exitOnly, receivedFor: "someone-else")
        files.advance(1)
        await process.crossing(.enter, Self.exitOnly)
        files.advance(1)
        process.contextStore.setUserId("user-b")
        process.contextStore.setUserId("user-a")

        await process.crossing(.exit, Self.exitOnly, at: exitedAt)

        let closed = try #require(await process.exitRows().last)
        #expect(closed.visitDurationSeconds == nil)
        #expect(closed.visitId == nil)
        files.advance(120)
        await process.crossing(.exit, Self.exitOnly)
        let rows = await process.exitRows()
        try #require(rows.count == 2)
        #expect(rows[1].visitDurationSeconds == nil)
    }

    /// The EXIT's facts were fixed before the user changed: the visit completed under A. A change
    /// away and back while the EXIT is being handed to the tracker delivers it as A, with the
    /// duration it carries; a change away to B drops it rather than giving it to B.
    @Test(arguments: [true, false])
    func identityChangeAfterTheExitWasTimedKeepsItsFactsOrDropsIt(backToTheSameUser: Bool) async throws {
        let files = Files()
        let process = await Process(files: files) { contextStore in
            contextStore.setUserId("user-b")
            if backToTheSameUser { contextStore.setUserId("user-a") }
        }
        let entry = files.clock.wall
        await process.crossing(.enter, Self.exitOnly)
        files.advance(75)

        await process.crossing(.exit, Self.exitOnly)

        let rows = await process.exitRows()
        if backToTheSameUser {
            try #require(rows.count == 1)
            #expect(rows[0].userId == "user-a")
            #expect(rows[0].enteredAt.map { Int($0.timeIntervalSince1970) } == Int(entry.timeIntervalSince1970))
            #expect(rows[0].visitDurationSeconds == 75)
        } else {
            #expect(rows.isEmpty)
        }
    }

    // MARK: - Legacy and unproven visits

    /// A visit a build before identity provenance persisted — observed entry and all — names no
    /// identity it was recorded under. Its EXIT ends it, untimed. The next stay, entered by a
    /// native crossing, is timed.
    @Test
    func legacyObservedVisitsExitIsUntimed() async throws {
        let files = Files()
        let process = await Process(files: files)
        let legacy = try await process.saveLegacyVisit(Self.exitOnly, entryObserved: true)
        files.advance(600)

        await process.crossing(.exit, Self.exitOnly)

        let untimed = try #require(await process.exitRows().last)
        #expect(untimed.visitDurationSeconds == nil)
        #expect(untimed.visitId == nil)
        files.advance(60)
        await process.crossing(.enter, Self.exitOnly)
        files.advance(45)
        await process.crossing(.exit, Self.exitOnly)
        let rows = await process.exitRows()
        try #require(rows.count == 2)
        #expect(rows[1].visitId != legacy.visitId)
        #expect(rows[1].visitDurationSeconds == 45)
    }

    /// A legacy unknown-entry candidate waits for proof. Its first fresh inside fix, five hours
    /// later, restarts it there: no DWELL, and its EXIT reports no entry or duration. A native
    /// ENTER after that is a stay of its own, which its EXIT times.
    @Test
    func legacyCandidateProvenLateIsUntimedAndANativeEnterIsTimed() async throws {
        let files = Files()
        let process = await Process(files: files)
        let legacy = try await process.saveLegacyVisit(Self.dwellCircle, entryObserved: false)
        files.advance(5 * 3600)

        await process.dwell.recordInsideEvidence(
            geofence: Self.dwellCircle, at: files.clock.wall, source: "location_evidence"
        )
        let proven = try #require(await process.storage.getDwellVisit(geofenceId: Self.dwellCircle.id))
        #expect(proven.visitId != legacy.visitId)
        #expect(proven.entryObserved == false)
        #expect(await process.rows(.dwell).isEmpty)
        files.advance(120)
        await process.crossing(.exit, Self.dwellCircle)
        let untimed = try #require(await process.exitRows().last)
        #expect(untimed.visitDurationSeconds == nil)
        #expect(untimed.enteredAt == nil)
        #expect(await process.rows(.dwell).isEmpty)

        files.advance(60)
        let entry = files.clock.wall
        await process.crossing(.enter, Self.dwellCircle)
        files.advance(90)
        await process.crossing(.exit, Self.dwellCircle)
        let rows = await process.exitRows()
        try #require(rows.count == 2)
        #expect(rows[1].enteredAt.map { Int($0.timeIntervalSince1970) } == Int(entry.timeIntervalSince1970))
        #expect(rows[1].visitDurationSeconds == 90)
        process.dwell.cancelEvidence(for: Self.dwellCircle.id)
    }

    /// A legacy visit whose dwell was already emitted, or reserved, keeps its id and facts: it is
    /// never qualified again and no DWELL row is added. Its EXIT is untimed.
    @Test(arguments: [true, false])
    func legacyEmittedOrReservedVisitKeepsItsFactsAndItsExitIsUntimed(emitted: Bool) async throws {
        let files = Files()
        let process = await Process(files: files)
        let reservation = emitted ? nil : GeofenceDwellReservation(
            occurredAtEpochMilliseconds: Int64(files.clock.wall.timeIntervalSince1970 * 1000),
            enteredAtEpochMilliseconds: nil, durationSeconds: nil, thresholdSeconds: 600,
            detectionSource: "location_evidence"
        )
        let legacy = try await process.saveLegacyVisit(
            Self.dwellCircle, entryObserved: false, emitted: emitted, reservation: reservation
        )
        let stored = try #require(await process.storage.getDwellVisit(geofenceId: Self.dwellCircle.id))
        #expect(stored.visitId == legacy.visitId)
        #expect(stored.emitted == emitted)
        #expect(stored.dwellReservation == reservation)
        #expect(stored.awaitsPresenceProof == false)
        files.advance(300)

        await process.crossing(.exit, Self.dwellCircle)

        let row = try #require(await process.exitRows().last)
        #expect(row.visitDurationSeconds == nil)
        #expect(row.visitId == nil)
        #expect(await process.rows(.dwell).isEmpty)
        process.dwell.cancelEvidence(for: Self.dwellCircle.id)
    }

    // MARK: - Superseding native ENTER

    /// The EXIT that ended a stay was lost. A native ENTER five hours later is a new crossing: the
    /// old visit ends there, and the next EXIT times only the new stay.
    @Test
    func laterNativeEnterAfterALostExitTimesOnlyTheNewStay() async throws {
        let files = Files()
        let process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly)
        let old = try #require(await process.storage.getDwellVisit(geofenceId: Self.exitOnly.id))
        files.advance(5 * 3600)
        let reentry = files.clock.wall

        await process.crossing(.enter, Self.exitOnly)
        files.advance(90)
        await process.crossing(.exit, Self.exitOnly)

        let row = try #require(await process.exitRows().last)
        #expect(row.visitId != old.visitId)
        #expect(row.enteredAt.map { Int($0.timeIntervalSince1970) } == Int(reentry.timeIntervalSince1970))
        #expect(row.visitDurationSeconds == 90)
    }

    // MARK: - First clock reading

    /// A cold wake handles an ENTER the OS dated before this process's first clock reading. With no
    /// reference from an earlier process, or one the wall clock has since stepped away from, that
    /// date cannot be placed on the current clock: the visit's EXIT reports no entry or duration.
    @Test(arguments: [false, true])
    func entryDatedBeforeTheFirstReadingOnAnUnknownClockIsUntimed(steppedSinceTheReference: Bool) async throws {
        let files = Files()
        if steppedSinceTheReference {
            let earlier = await Process(files: files)
            // Any boundary persists the process's clock reference.
            await earlier.crossing(.exit, Self.exitOnly)
            files.clock.stepWall(3600)
        }
        let enteredAt = files.clock.wall
        files.advance(20)

        let process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly, at: enteredAt)
        files.advance(60)
        await process.crossing(.exit, Self.exitOnly)

        let row = try #require(await process.exitRows().last)
        #expect(row.visitDurationSeconds == nil)
        #expect(row.enteredAt == nil)
    }

    /// Control: the same delayed ENTER on a clock an earlier process's reference shows unchanged
    /// keeps its entry, and its EXIT is timed from it.
    @Test
    func entryDatedBeforeTheFirstReadingOnAKnownClockIsTimed() async throws {
        let files = Files()
        let earlier = await Process(files: files)
        await earlier.crossing(.exit, Self.exitOnly)
        files.advance(10)
        let enteredAt = files.clock.wall
        files.advance(20)

        let process = await Process(files: files)
        await process.crossing(.enter, Self.exitOnly, at: enteredAt)
        files.advance(60)
        await process.crossing(.exit, Self.exitOnly)

        let row = try #require(await process.exitRows().last)
        #expect(row.enteredAt.map { Int($0.timeIntervalSince1970) } == Int(enteredAt.timeIntervalSince1970))
        #expect(row.visitDurationSeconds == 80)
    }

    // MARK: - Files and processes

    /// What survives a process: the files, and the device's clock.
    @MainActor
    private final class Files {
        let contextDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let geofenceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let clock = ManualGeofenceClock(wall: Date(timeIntervalSince1970: 1800000000))
        let dateUtil = DateUtilStub()
        var seeded = false

        init() {
            dateUtil.givenNow = clock.wall
        }

        /// Real time passes: both clocks, and the tracker's wall clock, move together.
        func advance(_ seconds: TimeInterval) {
            clock.advance(seconds)
            dateUtil.givenNow = clock.wall
        }
    }

    /// What a process builds at launch from those files.
    @MainActor
    private struct Process {
        let contextStore: BackgroundDeliveryContextStore
        let identity: GeofenceIdentityTracker
        let storage: GeofenceStorage
        let outbox: PendingGeofenceMetricStore
        let dwell: GeofenceDwellCoordinator
        let resolver: PolygonMembershipResolver
        let files: Files

        /// - Parameter beforeExitDelivery: runs as each EXIT reaches the tracker, after the
        ///   coordinator has fixed its facts.
        init(files: Files, beforeExitDelivery: ((BackgroundDeliveryContextStore) -> Void)? = nil) async {
            self.files = files
            self.contextStore = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: files.contextDirectory)
            self.storage = GeofenceStorage(fileManager: .default, directoryURL: files.geofenceDirectory)
            if !files.seeded {
                files.seeded = true
                contextStore.setUserId("user-a")
                contextStore.setCdpApiKey("cdp-key")
                let fences = [GeofenceExitDurationProvenanceTests.exitOnly, GeofenceExitDurationProvenanceTests.dwellCircle]
                await storage.setCachedGeofences(fences)
                await storage.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: Set(fences.map(\.id)))
            }
            self.identity = GeofenceIdentityTracker(contextStore: contextStore)
            self.outbox = PendingGeofenceMetricStore(
                logger: LoggerMock(), directoryURL: files.geofenceDirectory.appendingPathComponent("outbox")
            )
            let delivery = GeofenceDeliveryTrackerMock()
            delivery.trackMetricClosure = { _, _, onComplete in onComplete(.failure(.transport)) }
            let tracker = GeofenceEventTracker(
                storage: storage, pendingStore: outbox, deliveryTracker: delivery, contextStore: contextStore,
                eventBusHandler: EventBusHandlerMock(), dateUtil: files.dateUtil, logger: LoggerMock(),
                cooldownInterval: 0
            )
            let contextStore = contextStore
            let emitter: GeofenceTransitionEmitting = beforeExitDelivery.map { hook in
                ExitHandoff(tracker: tracker, contextStore: contextStore, hook: hook)
            } ?? tracker
            self.dwell = GeofenceDwellCoordinator(
                storage: storage, transitionEmitter: emitter, contextStore: contextStore, logger: LoggerMock(),
                notificationCenter: NotificationCenter(), freshFixProvider: { nil }, evidenceRetryDelay: 3600,
                clock: files.clock, identityTracker: identity
            )
            let fixResolver = MovementFixResolver(logger: LoggerMock(), dateUtil: files.dateUtil)
            fixResolver.systemCachedFix = { nil }
            fixResolver.requestFreshFix = { [weak fixResolver] in fixResolver?.handleRequestFailure() }
            self.resolver = PolygonMembershipResolver(
                storage: storage, transitionEmitter: emitter, logger: LoggerMock(), contextStore: contextStore,
                dateUtil: files.dateUtil, fixResolver: fixResolver, notificationCenter: NotificationCenter(),
                dwellCoordinator: dwell
            )
        }

        /// A Core Location crossing, routed as the monitor binder routes it: dated `at` (now by
        /// default) and received for whoever is identified, unless `receivedFor` says otherwise.
        func crossing(
            _ transition: GeofenceTransition,
            _ geofence: Geofence,
            at date: Date? = nil,
            receivedFor userId: String? = nil
        ) async {
            await resolver.handleTransition(
                identifier: geofence.id, transition: transition, occurredAt: date ?? files.clock.wall,
                receivedForUserId: userId ?? contextStore.currentUserId ?? ""
            )
        }

        /// Persists a visit through the real store as this build records it, then deletes from the
        /// bytes on disk the keys a build before identity provenance never wrote.
        func saveLegacyVisit(
            _ geofence: Geofence,
            entryObserved: Bool,
            emitted: Bool = false,
            reservation: GeofenceDwellReservation? = nil
        ) async throws -> GeofenceDwellVisit {
            let visit = GeofenceDwellVisit(
                visitId: UUID().uuidString, enteredAt: files.clock.wall, geometryRevision: geofence.dwellRevision,
                userId: "user-a", emitted: emitted, entryObserved: entryObserved, dwellReservation: reservation,
                timing: GeofenceVisitTiming(enteredAt: files.clock.wall, recordedAt: files.clock.read())
            )
            #expect(await storage.saveDwellVisit(visit, geofenceId: geofence.id))
            let file = files.geofenceDirectory.appendingPathComponent("geofenceState.json")
            var state = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            var visits = try #require(state["dwellVisits"] as? [String: Any])
            var stored = try #require(visits[geofence.id] as? [String: Any])
            #expect(stored.removeValue(forKey: "awaitsPresenceProof") != nil)
            #expect(stored.keys.contains("identityVersion"))
            stored.removeValue(forKey: "identityVersion")
            stored.removeValue(forKey: "identityLineage")
            visits[geofence.id] = stored
            state["dwellVisits"] = visits
            try JSONSerialization.data(withJSONObject: state).write(to: file, options: .atomic)
            return visit
        }

        func rows(_ transition: GeofenceTransition) async -> [PendingGeofenceMetric] {
            await outbox.rows().filter { $0.transition == transition }.sorted { $0.timestamp < $1.timestamp }
        }

        func exitRows() async -> [PendingGeofenceMetric] {
            await rows(.exit)
        }
    }

    /// Hands each EXIT to the real tracker after running `hook`: the point between the
    /// coordinator fixing the EXIT's facts and the tracker stamping its user.
    private final class ExitHandoff: GeofenceTransitionEmitting, @unchecked Sendable {
        let tracker: GeofenceEventTracker
        let contextStore: BackgroundDeliveryContextStore
        let hook: (BackgroundDeliveryContextStore) -> Void

        init(tracker: GeofenceEventTracker, contextStore: BackgroundDeliveryContextStore, hook: @escaping (BackgroundDeliveryContextStore) -> Void) {
            self.tracker = tracker
            self.contextStore = contextStore
            self.hook = hook
        }

        func trackTransition(geofenceId: String, transition: GeofenceTransition, occurredAt: Date) async {
            await tracker.trackTransition(geofenceId: geofenceId, transition: transition, occurredAt: occurredAt)
        }

        func trackDwell(
            geofenceId: String, occurredAt: Date, context: GeofenceDwellContext, expectedUserId: String?
        ) async -> Bool {
            await tracker.trackDwell(geofenceId: geofenceId, occurredAt: occurredAt, context: context, expectedUserId: expectedUserId)
        }

        func trackExit(
            geofenceId: String, occurredAt: Date, context: GeofenceExitContext?, expectedUserId: String?
        ) async {
            hook(contextStore)
            await tracker.trackExit(geofenceId: geofenceId, occurredAt: occurredAt, context: context, expectedUserId: expectedUserId)
        }
    }
}
