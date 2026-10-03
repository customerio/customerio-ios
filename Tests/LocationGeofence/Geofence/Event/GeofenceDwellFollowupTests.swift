@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import CoreLocation
import Foundation
import SharedTests
import Testing

/// Dwell continuity driven through the producers that feed it: the sync coordinator's initial
/// ENTER, the monitor binder, the fix resolver. Every DWELL is read back from a real tracker's
/// outbox; only the clock, the fixes, the API and the HTTP transport are scripted.
@Suite("GeofenceDwellFollowup", .serialized)
@MainActor
struct GeofenceDwellFollowupTests {
    /// 150 m around (1, 2); 0.01° of latitude is about 1.1 km.
    private static let circle = Geofence(
        id: "circle", latitude: 1, longitude: 2, radius: 150, name: "circle",
        transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1),
        dwellThresholdSeconds: 600
    )

    // MARK: - F1: a discovery candidate from the refresh anchor

    /// The refresh anchors on a stored location inside the circle while the device is elsewhere,
    /// and the app is suspended before any fix. Five hours later the first fresh fix is inside: it
    /// is the first proof of presence, not the end of a five-hour stay, so no DWELL yet. The stay
    /// it proves qualifies after the threshold, with no entry or duration reported.
    @Test
    func discoveryFromAStaleAnchorNeedsFreshProofBeforeTimeCounts() async throws {
        let rig = await Rig.make()
        await rig.refreshAnchoredInsideTheCircle()
        let discovered = try #require(await rig.storage.getDwellVisit(geofenceId: Self.circle.id))
        #expect(discovered.entryObserved == false)

        rig.advance(5 * 3600)
        rig.fixes.queue(rig.fix(latitudeOffset: 0, accuracy: 10))
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        #expect(await rig.dwellRows().isEmpty)

        rig.advance(600)
        rig.fixes.queue(rig.fix(latitudeOffset: 0, accuracy: 10))
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        let rows = await rig.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].enteredAt == nil)
        #expect(rows[0].dwellDurationSeconds == nil)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// The OS ENTER for the real arrival lands five hours after the discovery. The threshold counts
    /// from that ENTER, which is an observed entry: a fresh inside fix right after it is no DWELL,
    /// and the DWELL after the threshold reports that ENTER.
    @Test
    func osEnterAfterAnUnprovenDiscoveryStartsItsOwnStay() async throws {
        let rig = await Rig.make()
        await rig.refreshAnchoredInsideTheCircle()
        let discovered = try #require(await rig.storage.getDwellVisit(geofenceId: Self.circle.id))

        rig.advance(5 * 3600)
        let enteredAt = rig.clock.wall
        await rig.dwell.handleBoundary(geofence: Self.circle, transition: .enter, occurredAt: enteredAt)
        rig.fixes.queue(rig.fix(latitudeOffset: 0, accuracy: 10))
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        #expect(await rig.dwellRows().isEmpty)
        let stay = try #require(await rig.storage.getDwellVisit(geofenceId: Self.circle.id))
        #expect(stay.visitId != discovered.visitId)

        rig.advance(600)
        rig.fixes.queue(rig.fix(latitudeOffset: 0, accuracy: 10))
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        let rows = await rig.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId == stay.visitId)
        #expect(rows[0].enteredAt == enteredAt)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// Control: a fresh, accurate fix wholly inside right at discovery proves presence then, and a
    /// long silent gap before the next fresh inside fix takes nothing from the stay. No gap cutoff.
    @Test
    func discoveryProvenAtOnceStillQualifiesAfterALongSilentGap() async throws {
        let rig = await Rig.make()
        await rig.refreshAnchoredInsideTheCircle()
        rig.fixes.queue(rig.fix(latitudeOffset: 0, accuracy: 10))
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)
        await settleQuietly()

        rig.advance(5 * 3600)
        rig.fixes.queue(rig.fix(latitudeOffset: 0, accuracy: 10))
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        let rows = await rig.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].enteredAt == nil)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    // MARK: - O1: a later native ENTER while an older visit is held

    /// The EXIT of an observed visit was lost. The next native ENTER is a crossing — Core Location
    /// reports only crossings, `CLMonitor` drops a same-state repeat — so it starts a stay of its
    /// own: a fresh inside fix right after it is no DWELL, and nothing reports the old entry. The
    /// new stay qualifies after the threshold.
    @Test
    func laterNativeEnterAfterALostExitStartsANewStay() async throws {
        let rig = await Rig.make()
        await rig.cacheCircle()
        let firstEntry = rig.clock.wall
        await rig.dwell.handleBoundary(geofence: Self.circle, transition: .enter, occurredAt: firstEntry)
        let first = try #require(await rig.storage.getDwellVisit(geofenceId: Self.circle.id))

        rig.advance(5 * 3600)
        let reentry = rig.clock.wall
        await rig.dwell.handleBoundary(geofence: Self.circle, transition: .enter, occurredAt: reentry)
        await rig.dwell.recordInsideEvidence(geofence: Self.circle, at: rig.clock.wall, source: "location_evidence")

        #expect(await rig.dwellRows().isEmpty)
        let stay = try #require(await rig.storage.getDwellVisit(geofenceId: Self.circle.id))
        #expect(stay.visitId != first.visitId)

        rig.advance(600)
        await rig.dwell.recordInsideEvidence(geofence: Self.circle, at: rig.clock.wall, source: "location_evidence")
        let rows = await rig.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId == stay.visitId)
        #expect(rows[0].enteredAt == reentry)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// Control: a copy of the same ENTER — same date — is the same visit, and leaves its emitted
    /// DWELL, reservation and queued row exactly as they were.
    @Test
    func sameDatedEnterCopyKeepsTheVisitAndItsQueuedDwell() async throws {
        let rig = await Rig.make()
        await rig.cacheCircle()
        let enteredAt = rig.clock.wall
        await rig.dwell.handleBoundary(geofence: Self.circle, transition: .enter, occurredAt: enteredAt)
        rig.advance(600)
        await rig.dwell.recordInsideEvidence(geofence: Self.circle, at: rig.clock.wall, source: "location_evidence")
        let emitted = try #require(await rig.storage.getDwellVisit(geofenceId: Self.circle.id))
        #expect(emitted.emitted)
        let rowsBefore = await rig.dwellRows()

        rig.advance(5)
        await rig.dwell.handleBoundary(geofence: Self.circle, transition: .enter, occurredAt: enteredAt)

        #expect(await rig.storage.getDwellVisit(geofenceId: Self.circle.id) == emitted)
        #expect(await rig.dwellRows() == rowsBefore)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// The facts a replaced visit already queued stay queued as they were.
    @Test
    func laterNativeEnterLeavesTheOldVisitsQueuedDwell() async throws {
        let rig = await Rig.make()
        await rig.cacheCircle()
        await rig.dwell.handleBoundary(geofence: Self.circle, transition: .enter, occurredAt: rig.clock.wall)
        rig.advance(600)
        await rig.dwell.recordInsideEvidence(geofence: Self.circle, at: rig.clock.wall, source: "location_evidence")
        let rowsBefore = await rig.dwellRows()
        try #require(rowsBefore.count == 1)

        rig.advance(3600)
        await rig.dwell.handleBoundary(geofence: Self.circle, transition: .enter, occurredAt: rig.clock.wall)

        #expect(await rig.dwellRows() == rowsBefore)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// The binder re-arms every visit's evidence before it routes the ENTER that woke it. The
    /// re-armed deadline of the old visit is long due, and a fresh inside fix answers at once: it
    /// must not qualify that visit ahead of the ENTER that replaces it.
    @Test
    func binderRearmAheadOfALaterEnterCannotQualifyTheOldVisit() async throws {
        let rig = await Rig.make(insideFixAlways: true)
        await rig.cacheCircle()
        await rig.dwell.handleBoundary(geofence: Self.circle, transition: .enter, occurredAt: rig.clock.wall)
        let first = try #require(await rig.storage.getDwellVisit(geofenceId: Self.circle.id))
        rig.dwell.cancelEvidence(for: Self.circle.id)
        rig.advance(5 * 3600)
        let monitor = MockGeofenceRegionMonitor()
        let sync = GeofenceSyncCoordinatorMock()
        sync.refreshReturnValue = .success(())
        sync.handleMovementReturnValue = .success(())
        let resolver = PolygonMembershipResolver(
            storage: rig.storage, transitionEmitter: rig.tracker, logger: LoggerMock(), contextStore: rig.contextStore,
            dateUtil: rig.dateUtil, notificationCenter: NotificationCenter(), dwellCoordinator: rig.dwell
        )
        GeofenceMonitorBinder.bind(
            monitor: monitor, resolver: resolver, coordinator: sync, logger: LoggerMock(), dwellCoordinator: rig.dwell
        )

        monitor.simulateTransition(
            identifier: Self.circle.id, transition: .enter, location: nil, occurredAt: rig.clock.wall
        )
        // What the re-armed, long-due deadline does, run ahead of the routed ENTER.
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)
        // Let the routed ENTER land.
        await settleQuietly(0.5)

        #expect(await rig.dwellRows().filter { $0.visitId == first.visitId }.isEmpty)
        #expect(await rig.storage.getDwellVisit(geofenceId: Self.circle.id)?.visitId != first.visitId)
        rig.dwell.cancelEvidence(for: Self.circle.id)
        withExtendedLifetime(resolver) {}
    }

    // MARK: - O2: fixes dated before a backward clock step

    /// The fix resolver last delivered an inside fix; then the device left, the clock was set back
    /// an hour, and a new visit began. That old fix now reads as from the future, not as fresh: the
    /// circle's evidence asks for a new fix, which is outside, so no DWELL. A new fresh inside fix
    /// on the current clock still qualifies the next stay.
    @Test
    func fixDatedBeforeABackwardStepIsNotFreshEvidence() async throws {
        let rig = await Rig.make(realFixResolver: true)
        await rig.cacheCircle(threshold: 60)
        rig.fixResolver?.handleDeliveredFix(rig.fix(latitudeOffset: 0, accuracy: 10))
        rig.advance(10)
        rig.stepWall(-3600)
        rig.advance(10)
        await rig.dwell.handleBoundary(geofence: Self.circleWith(threshold: 60), transition: .enter, occurredAt: rig.clock.wall)
        rig.advance(120)

        rig.fixes.queue(rig.fix(latitudeOffset: 0.01, accuracy: 10))
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        #expect(await rig.dwellRows().isEmpty)
        #expect(await rig.storage.getDwellVisit(geofenceId: Self.circle.id) == nil)

        rig.advance(30)
        await rig.dwell.handleBoundary(geofence: Self.circleWith(threshold: 60), transition: .enter, occurredAt: rig.clock.wall)
        rig.advance(120)
        rig.fixes.queue(rig.fix(latitudeOffset: 0, accuracy: 10))
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        #expect(await rig.dwellRows().count == 1)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// A pass handed a held fix dated in the future of the current clock cannot know when it was
    /// taken. The polygon decision already refuses a negative age; the same fix, wholly outside a
    /// circle, must not end that circle's visit either.
    @Test
    func passIgnoresAHeldFixDatedInTheFuture() async throws {
        let rig = await Rig.make(realFixResolver: true)
        let polygon = Geofence(
            id: "polygon", latitude: 0, longitude: 0, radius: 300, name: "polygon",
            transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1),
            vertices: [
                LocationData(latitude: -0.0016, longitude: -0.0016),
                LocationData(latitude: -0.0016, longitude: 0.0016),
                LocationData(latitude: 0.0016, longitude: 0.0016),
                LocationData(latitude: 0.0016, longitude: -0.0016)
            ]
        )
        await rig.storage.setCachedGeofences([polygon, Self.circle])
        await rig.storage.recordRegistration(
            center: LocationData(latitude: 0, longitude: 0), businessIds: [polygon.id, Self.circle.id]
        )
        await rig.dwell.handleBoundary(geofence: Self.circle, transition: .enter, occurredAt: rig.clock.wall)
        let visit = try #require(await rig.storage.getDwellVisit(geofenceId: Self.circle.id))
        rig.dwell.cancelEvidence(for: Self.circle.id)
        rig.advance(30)
        let resolver = PolygonMembershipResolver(
            storage: rig.storage, transitionEmitter: rig.tracker, logger: LoggerMock(), contextStore: rig.contextStore,
            dateUtil: rig.dateUtil, fixResolver: rig.fixResolver, notificationCenter: NotificationCenter(),
            dwellCoordinator: rig.dwell
        )
        // Inside the polygon, about 220 km from the circle.
        let futureFix = ResolvedFix(
            latitude: 0, longitude: 0, horizontalAccuracy: 5, timestamp: rig.clock.wall.addingTimeInterval(3600)
        )

        await resolver.evaluateAllPolygons(reason: .movement, heldFix: futureFix)

        #expect(await rig.storage.getPolygonMembership()[polygon.id] == nil)
        #expect(await rig.outbox.rows().filter { $0.geofenceId == polygon.id }.isEmpty)
        #expect(await rig.storage.getDwellVisit(geofenceId: Self.circle.id)?.visitId == visit.visitId)
    }

    // MARK: - O3: a stale snapshot that tracks no visit

    /// An ENTER judged against a snapshot read before the refresh that enabled the dwell must not
    /// delete the visit recorded under the enabled fence.
    @Test
    func enterWithAStaleUntrackedSnapshotLeavesTheVisit() async throws {
        let rig = await Rig.make()
        await rig.cacheCircle()
        await rig.dwell.handleBoundary(geofence: Self.circle, transition: .enter, occurredAt: rig.clock.wall)
        let visit = try #require(await rig.storage.getDwellVisit(geofenceId: Self.circle.id))

        rig.advance(5)
        await rig.dwell.handleBoundary(geofence: Self.circleWith(threshold: 0), transition: .enter, occurredAt: rig.clock.wall)

        #expect(await rig.storage.getDwellVisit(geofenceId: Self.circle.id)?.visitId == visit.visitId)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// Control: disabling the dwell in the cache still removes the visit.
    @Test
    func disablingTheDwellInTheCacheStillRemovesTheVisit() async throws {
        let rig = await Rig.make()
        await rig.cacheCircle()
        await rig.dwell.handleBoundary(geofence: Self.circle, transition: .enter, occurredAt: rig.clock.wall)
        #expect(await rig.storage.getDwellVisit(geofenceId: Self.circle.id) != nil)

        await rig.storage.setCachedGeofences([Self.circleWith(threshold: 0)])

        #expect(await rig.storage.getDwellVisit(geofenceId: Self.circle.id) == nil)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    // MARK: - O4: an entry dated before this process first read the clock

    /// The ENTER is dated, the wall clock steps forward an hour, and only then does a new process
    /// read the clock for the first time. Nothing this process saw places that date on its clock,
    /// so the dwell still qualifies on time since it was recorded but reports no entry or duration.
    @Test
    func entryDatedBeforeAStepAheadOfTheProcessesFirstReadingReportsNoEntry() async throws {
        let rig = await Rig.make()
        await rig.cacheCircle()
        await rig.dwell.handleBoundary(geofence: Self.circle, transition: .exit, occurredAt: rig.clock.wall)
        rig.advance(100)
        let enteredAt = rig.clock.wall
        rig.stepWall(3600)
        rig.advance(10)

        let relaunched = rig.relaunch()
        await relaunched.handleBoundary(geofence: Self.circle, transition: .enter, occurredAt: enteredAt)
        rig.advance(600)
        await relaunched.recordInsideEvidence(geofence: Self.circle, at: rig.clock.wall, source: "location_evidence")

        let rows = await rig.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].enteredAt == nil)
        #expect(rows[0].dwellDurationSeconds == nil)
        relaunched.cancelEvidence(for: Self.circle.id)
    }

    /// Control: with no step since the earlier process last read the clock, the same delayed ENTER
    /// is on the current clock and its entry and duration are reported.
    @Test
    func entryDatedAheadOfTheProcessesFirstReadingOnAnUnchangedClockReportsItsEntry() async throws {
        let rig = await Rig.make()
        await rig.cacheCircle()
        await rig.dwell.handleBoundary(geofence: Self.circle, transition: .exit, occurredAt: rig.clock.wall)
        rig.advance(100)
        let enteredAt = rig.clock.wall
        rig.advance(10)

        let relaunched = rig.relaunch()
        await relaunched.handleBoundary(geofence: Self.circle, transition: .enter, occurredAt: enteredAt)
        rig.advance(600)
        await relaunched.recordInsideEvidence(geofence: Self.circle, at: rig.clock.wall, source: "location_evidence")

        let rows = await rig.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].enteredAt == enteredAt)
        #expect(rows[0].dwellDurationSeconds == 610)
        relaunched.cancelEvidence(for: Self.circle.id)
    }

    // MARK: - Legacy visits persisted before `awaitsPresenceProof`

    /// The build before this field persisted stale-anchor discoveries as unknown-entry, unemitted,
    /// unreserved candidates. Read back without the key, such a candidate must still await its
    /// first proof: five hours on, the first fresh inside fix proves presence and qualifies
    /// nothing. The stay it proves qualifies after the threshold, with no entry or duration.
    @Test
    func legacyUnknownEntryCandidateAwaitsItsFirstProof() async throws {
        let rig = await Rig.make()
        await rig.cacheCircle()
        let legacy = try await rig.saveLegacyVisit(entryObserved: false)

        rig.advance(5 * 3600)
        let relaunched = rig.relaunch()
        rig.fixes.queue(rig.fix(latitudeOffset: 0, accuracy: 10))
        await relaunched.requestQualifyingEvidence(geofenceId: Self.circle.id)

        #expect(await rig.dwellRows().isEmpty)
        #expect(await rig.storage.getDwellVisit(geofenceId: Self.circle.id)?.visitId != legacy.visitId)

        rig.advance(600)
        rig.fixes.queue(rig.fix(latitudeOffset: 0, accuracy: 10))
        await relaunched.requestQualifyingEvidence(geofenceId: Self.circle.id)
        let rows = await rig.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].enteredAt == nil)
        #expect(rows[0].dwellDurationSeconds == nil)
        relaunched.cancelEvidence(for: Self.circle.id)
    }

    /// Control: a legacy visit whose dwell was already emitted keeps its id and state; nothing new
    /// is queued for it.
    @Test
    func legacyEmittedVisitStaysAsItWas() async throws {
        let rig = await Rig.make()
        await rig.cacheCircle()
        let legacy = try await rig.saveLegacyVisit(entryObserved: false, emitted: true)

        rig.advance(5 * 3600)
        let relaunched = rig.relaunch()
        await relaunched.recordInsideEvidence(geofence: Self.circle, at: rig.clock.wall, source: "location_evidence")

        let stored = await rig.storage.getDwellVisit(geofenceId: Self.circle.id)
        #expect(stored?.visitId == legacy.visitId)
        #expect(stored?.emitted == true)
        #expect(stored?.awaitsPresenceProof == false)
        #expect(await rig.dwellRows().isEmpty)
        relaunched.cancelEvidence(for: Self.circle.id)
    }

    /// Control: a legacy visit whose dwell was reserved but never queued delivers that reservation
    /// unchanged, under its own visit id.
    @Test
    func legacyReservedVisitDeliversItsReservation() async throws {
        let rig = await Rig.make()
        await rig.cacheCircle()
        let reservation = GeofenceDwellReservation(
            occurredAtEpochMilliseconds: Int64(rig.clock.wall.timeIntervalSince1970 * 1000) + 600000,
            enteredAtEpochMilliseconds: nil, durationSeconds: nil, thresholdSeconds: 600,
            detectionSource: "location_evidence"
        )
        let legacy = try await rig.saveLegacyVisit(entryObserved: false, reservation: reservation)

        rig.advance(5 * 3600)
        let relaunched = rig.relaunch()
        await relaunched.requestQualifyingEvidence(geofenceId: Self.circle.id)

        let rows = await rig.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId == legacy.visitId)
        // Epoch milliseconds: the outbox stores the date as floating seconds.
        #expect(Int64((rows[0].timestamp.timeIntervalSince1970 * 1000).rounded()) == reservation.occurredAtEpochMilliseconds)
        relaunched.cancelEvidence(for: Self.circle.id)
    }

    /// A legacy visit with an observed entry carries no identity provenance either: nothing says
    /// whether another user was identified during it. Its first fresh proof starts the stay over,
    /// and the stay reports no entry or duration it cannot vouch for.
    @Test
    func legacyObservedVisitRestartsAtItsFirstProof() async throws {
        let rig = await Rig.make()
        await rig.cacheCircle()
        let legacy = try await rig.saveLegacyVisit(entryObserved: true)

        rig.advance(600)
        let relaunched = rig.relaunch()
        await relaunched.recordInsideEvidence(geofence: Self.circle, at: rig.clock.wall, source: "location_evidence")

        #expect(await rig.dwellRows().isEmpty)
        #expect(await rig.storage.getDwellVisit(geofenceId: Self.circle.id)?.visitId != legacy.visitId)
        rig.advance(600)
        await relaunched.recordInsideEvidence(geofence: Self.circle, at: rig.clock.wall, source: "location_evidence")
        let rows = await rig.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].enteredAt == nil)
        #expect(rows[0].dwellDurationSeconds == nil)
        relaunched.cancelEvidence(for: Self.circle.id)
    }

    /// Control: an unknown-entry visit this build persisted with an explicit `false` — proven by
    /// an OS correction or a fresh fix — qualifies on its recorded time.
    @Test
    func provenUnknownEntryVisitWithTheFlagQualifies() async throws {
        let rig = await Rig.make()
        await rig.cacheCircle()
        let visit = rig.makeVisit(entryObserved: false)
        #expect(await rig.storage.saveDwellVisit(visit, geofenceId: Self.circle.id))

        rig.advance(600)
        let relaunched = rig.relaunch()
        await relaunched.recordInsideEvidence(geofence: Self.circle, at: rig.clock.wall, source: "location_evidence")

        #expect(await rig.dwellRows().map(\.visitId) == [visit.visitId])
        relaunched.cancelEvidence(for: Self.circle.id)
    }

    // MARK: - Rig

    private static func circleWith(threshold: Int) -> Geofence {
        Geofence(
            id: circle.id, latitude: circle.latitude, longitude: circle.longitude, radius: circle.radius,
            name: circle.name, transitionTypes: circle.transitionTypes, lastUpdated: circle.lastUpdated,
            dwellThresholdSeconds: threshold
        )
    }

    @MainActor
    final class FixQueue {
        private var fixes: [CLLocation] = []

        func queue(_ fix: CLLocation) {
            fixes.append(fix)
        }

        func next() -> CLLocation? {
            fixes.isEmpty ? nil : fixes.removeFirst()
        }
    }

    @MainActor
    final class Rig {
        let directory: URL
        let storage: GeofenceStorage
        let outbox: PendingGeofenceMetricStore
        let tracker: GeofenceEventTracker
        let contextStore: BackgroundDeliveryContextStore
        let clock: ManualGeofenceClock
        let dateUtil: DateUtilStub
        let fixes = FixQueue()
        let fixResolver: MovementFixResolver?
        let insideFixAlways: Bool
        private(set) var dwell: GeofenceDwellCoordinator!

        private init(realFixResolver: Bool, insideFixAlways: Bool) {
            self.directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            self.storage = GeofenceStorage(fileManager: .default, directoryURL: directory)
            self.outbox = PendingGeofenceMetricStore(logger: LoggerMock(), directoryURL: directory.appendingPathComponent("outbox"))
            self.contextStore = BackgroundDeliveryContextStore(
                fileManager: .default,
                directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            )
            contextStore.setUserId("user-1")
            self.clock = ManualGeofenceClock(wall: Date(timeIntervalSince1970: 1789215000))
            self.dateUtil = DateUtilStub()
            dateUtil.givenNow = clock.wall
            // Delivery fails, so every row stays in the outbox to be read.
            let delivery = GeofenceDeliveryTrackerMock()
            delivery.trackMetricClosure = { _, _, onComplete in onComplete(.failure(.transport)) }
            self.tracker = GeofenceEventTracker(
                storage: storage, pendingStore: outbox, deliveryTracker: delivery, contextStore: contextStore,
                eventBusHandler: EventBusHandlerMock(), dateUtil: dateUtil, logger: LoggerMock()
            )
            self.insideFixAlways = insideFixAlways
            self.fixResolver = realFixResolver ? MovementFixResolver(logger: LoggerMock(), dateUtil: dateUtil) : nil
        }

        static func make(realFixResolver: Bool = false, insideFixAlways: Bool = false) async -> Rig {
            let rig = Rig(realFixResolver: realFixResolver, insideFixAlways: insideFixAlways)
            if let fixResolver = rig.fixResolver {
                fixResolver.systemCachedFix = { nil }
                fixResolver.requestFreshFix = { [weak rig, weak fixResolver] in
                    guard let fix = rig?.fixes.next() else { return fixResolver?.handleRequestFailure() ?? () }
                    fixResolver?.handleDeliveredFix(fix)
                }
            }
            rig.dwell = rig.makeCoordinator()
            return rig
        }

        /// A new coordinator over the same storage and clock: a new process on the same boot.
        func relaunch() -> GeofenceDwellCoordinator {
            dwell.cancelEvidence(for: GeofenceDwellFollowupTests.circle.id)
            dwell = makeCoordinator()
            return dwell
        }

        private func makeCoordinator() -> GeofenceDwellCoordinator {
            GeofenceDwellCoordinator(
                storage: storage, transitionEmitter: tracker, contextStore: contextStore, logger: LoggerMock(),
                fixResolver: fixResolver, notificationCenter: NotificationCenter(),
                freshFixProvider: fixResolver != nil ? nil : { [weak self] in
                    guard let self else { return nil }
                    return self.insideFixAlways ? self.fix(latitudeOffset: 0, accuracy: 10) : self.fixes.next()
                },
                // Retries never fire within a test; each test asks for evidence itself.
                evidenceRetryDelay: 3600,
                clock: clock
            )
        }

        func advance(_ seconds: TimeInterval) {
            clock.advance(seconds)
            dateUtil.givenNow = clock.wall
        }

        func stepWall(_ seconds: TimeInterval) {
            clock.stepWall(seconds)
            dateUtil.givenNow = clock.wall
        }

        /// A fix taken now, `latitudeOffset` degrees north of the circle's centre.
        func fix(latitudeOffset: Double, accuracy: Double) -> CLLocation {
            CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: GeofenceDwellFollowupTests.circle.latitude + latitudeOffset,
                    longitude: GeofenceDwellFollowupTests.circle.longitude
                ),
                altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 10, timestamp: clock.wall
            )
        }

        func cacheCircle(threshold: Int = 600) async {
            let circle = GeofenceDwellFollowupTests.circleWith(threshold: threshold)
            await storage.setCachedGeofences([circle])
            await storage.recordRegistration(
                center: LocationData(latitude: circle.latitude, longitude: circle.longitude), businessIds: [circle.id]
            )
        }

        /// A remote refresh anchored on a stored location inside the circle — not a live fix —
        /// registers it as new, so the sync coordinator discovers the device inside it.
        func refreshAnchoredInsideTheCircle() async {
            let circle = GeofenceDwellFollowupTests.circle
            await storage.recordSync(
                timestamp: dateUtil.givenNow.addingTimeInterval(-25 * 3600), location: LocationData(latitude: 0, longitude: 0)
            )
            let api = GeofenceApiServiceMock()
            api.fetchNearbyGeofencesClosure = { _, _, completion in
                completion(.success(GeofenceApiResponse(config: nil, geofences: [
                    GeofenceApiRegion(
                        id: circle.id, name: circle.name, shape: "circle",
                        latitude: circle.latitude, longitude: circle.longitude, radius: circle.radius,
                        geometry: nil, enclosingCircle: nil, carriesPolygonFields: false, externalId: nil,
                        transitionTypes: circle.transitionTypes.map(\.rawValue),
                        lastUpdated: circle.lastUpdated.timeIntervalSince1970,
                        geosetIds: nil, metadata: nil, dwellThresholdSeconds: circle.dwellThresholdSeconds
                    )
                ])))
            }
            let dwell = dwell!
            let resolver = PolygonMembershipResolver(
                storage: storage, transitionEmitter: tracker, logger: LoggerMock(), contextStore: contextStore,
                dateUtil: dateUtil, notificationCenter: NotificationCenter(), dwellCoordinator: dwell
            )
            let sync = GeofenceSyncCoordinatorImpl(
                apiService: api, storage: storage, monitor: MockGeofenceRegionMonitor(), contextStore: contextStore,
                transitionEmitter: tracker, dwellCoordinator: dwell, polygonResolver: { resolver },
                dateUtil: dateUtil, logger: LoggerMock()
            )
            _ = await sync.refresh(latitude: circle.latitude, longitude: circle.longitude, anchorIsLiveFix: false)
            // The initial ENTER and its visit are written on a task of their own.
            for _ in 0 ..< 200 where await storage.getDwellVisit(geofenceId: circle.id) == nil {
                try? await Task.sleep(nanoseconds: 10000000)
            }
            withExtendedLifetime(resolver) {}
        }

        /// A visit on the circle as this build records it, entered now.
        func makeVisit(
            entryObserved: Bool, emitted: Bool = false, reservation: GeofenceDwellReservation? = nil
        ) -> GeofenceDwellVisit {
            GeofenceDwellVisit(
                visitId: UUID().uuidString, enteredAt: clock.wall,
                geometryRevision: GeofenceDwellFollowupTests.circle.dwellRevision, userId: "user-1",
                emitted: emitted, entryObserved: entryObserved, dwellReservation: reservation,
                timing: GeofenceVisitTiming(enteredAt: clock.wall, recordedAt: clock.read())
            )
        }

        /// Persists a visit through the real store, then deletes from the bytes on disk the two keys
        /// 291cb689 never wrote — `awaitsPresenceProof` and `identityVersion` — leaving exactly what
        /// that build stored.
        func saveLegacyVisit(
            entryObserved: Bool, emitted: Bool = false, reservation: GeofenceDwellReservation? = nil
        ) async throws -> GeofenceDwellVisit {
            let visit = makeVisit(entryObserved: entryObserved, emitted: emitted, reservation: reservation)
            #expect(await storage.saveDwellVisit(visit, geofenceId: GeofenceDwellFollowupTests.circle.id))
            let file = directory.appendingPathComponent("geofenceState.json")
            var state = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            var visits = try #require(state["dwellVisits"] as? [String: Any])
            var stored = try #require(visits[GeofenceDwellFollowupTests.circle.id] as? [String: Any])
            #expect(stored.removeValue(forKey: "awaitsPresenceProof") != nil)
            stored.removeValue(forKey: "identityVersion")
            visits[GeofenceDwellFollowupTests.circle.id] = stored
            state["dwellVisits"] = visits
            try JSONSerialization.data(withJSONObject: state).write(to: file, options: .atomic)
            return visit
        }

        func dwellRows() async -> [PendingGeofenceMetric] {
            await outbox.rows().filter { $0.transition == .dwell }
        }
    }
}
