@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import Foundation
import SharedTests
import Testing

/// A native ENTER is noted twice: synchronously by the binder as the OS delivers it, and again by
/// `handleBoundary` once its routing task runs. Routing tasks can run late, so an older ENTER's
/// second note can be processed after a later ENTER's first. On one wall-clock timeline, the later
/// crossing must stay noted. The chronology is driven at the coordinator: `noteEnter(geofenceId:
/// occurredAt:crossing:)` is the exact call the binder makes, and `handleBoundary` is what the
/// routing task calls, run here late. Storage, tracker, outbox and the fresh circle fix are real
/// (`GeofenceDwellFollowupTests.Rig`); only the clock and the fix are scripted, and HTTP fails so
/// every row stays in the outbox.
@Suite("GeofenceDwellEnterRenote", .serialized)
@MainActor
struct GeofenceDwellEnterRenoteTests {
    /// The rig's circle: 150 m around (1, 2), dwell after 600 s.
    private static let circle = Geofence(
        id: "circle", latitude: 1, longitude: 2, radius: 150, name: "circle",
        transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1),
        dwellThresholdSeconds: 600
    )

    /// ENTER at 0 starts a stay no fix has qualified yet. The OS repeats it at 0.2; the binder
    /// notes the copy, and its routing is held. At 600 a new ENTER follows an EXIT the SDK never
    /// got, and the binder notes it. The copy's routing then runs. A fresh inside fix at 600 —
    /// what the new ENTER's re-arm asks for — must not qualify the old stay across the departure
    /// that ENTER already proved; the new stay qualifies after its own 600 s.
    @Test(arguments: [true, false])
    func delayedCopyOfAnOlderEnter_expectTheLaterEnterStillEndsTheUnqualifiedStay(crossing: Bool) async throws {
        let rig = await Self.rig()
        let start = rig.clock.wall
        let first = try await Self.enter(rig, at: start, crossing: crossing)
        rig.advance(0.2)
        rig.dwell.noteEnter(geofenceId: Self.circle.id, occurredAt: start.addingTimeInterval(0.2), crossing: crossing)
        rig.advance(599.8)
        let later = rig.clock.wall
        rig.dwell.noteEnter(geofenceId: Self.circle.id, occurredAt: later, crossing: crossing)
        rig.advance(0.1)
        await Self.route(rig, at: start.addingTimeInterval(0.2), crossing: crossing)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        #expect(await rig.dwellRows().isEmpty)
        await Self.route(rig, at: later, crossing: crossing)
        let next = try #require(await rig.storage.getDwellVisit(geofenceId: Self.circle.id))
        #expect(next.visitId != first.visitId)
        rig.advance(600)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        let rows = await rig.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId == next.visitId)
        #expect(rows[0].enteredAt == (crossing ? later : nil))
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// Control: the same race with corrections, over a stay whose dwell went out. A correction
    /// does not end it, whichever note lands last, and it never qualifies again.
    @Test
    func delayedCopyOfAnOlderCorrection_expectTheEmittedStayKeptWithItsOneDwell() async throws {
        let rig = await Self.rig()
        let first = try await Self.enter(rig, at: rig.clock.wall, crossing: true)
        rig.advance(600)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)
        try #require(await rig.storage.getDwellVisit(geofenceId: Self.circle.id)?.emitted == true)

        let older = rig.clock.wall
        rig.dwell.noteEnter(geofenceId: Self.circle.id, occurredAt: older, crossing: false)
        rig.advance(600)
        let later = rig.clock.wall
        rig.dwell.noteEnter(geofenceId: Self.circle.id, occurredAt: later, crossing: false)
        rig.advance(0.1)
        await Self.route(rig, at: older, crossing: false)
        await Self.route(rig, at: later, crossing: false)
        rig.advance(600)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        #expect(await rig.dwellRows().map(\.visitId) == [first.visitId])
        #expect(await rig.storage.getDwellVisit(geofenceId: Self.circle.id)?.visitId == first.visitId)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// Control: the same over a dwell reserved but not yet queued. It is delivered as reserved,
    /// once, under its own visit id.
    @Test
    func delayedCopyOfAnOlderCorrection_expectAReservedDwellDeliveredAsReserved() async throws {
        let rig = await Self.rig()
        let start = rig.clock.wall
        let reservation = GeofenceDwellReservation(
            occurredAtEpochMilliseconds: Int64(start.timeIntervalSince1970 * 1000) + 600000,
            enteredAtEpochMilliseconds: Int64(start.timeIntervalSince1970 * 1000), durationSeconds: 600,
            thresholdSeconds: 600, detectionSource: "location_evidence"
        )
        let reserved = rig.makeVisit(entryObserved: true, reservation: reservation)
        try #require(await rig.storage.saveDwellVisit(reserved, geofenceId: Self.circle.id))
        rig.advance(700)

        let older = rig.clock.wall
        rig.dwell.noteEnter(geofenceId: Self.circle.id, occurredAt: older, crossing: false)
        rig.advance(600)
        let later = rig.clock.wall
        rig.dwell.noteEnter(geofenceId: Self.circle.id, occurredAt: later, crossing: false)
        rig.advance(0.1)
        await Self.route(rig, at: older, crossing: false)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)
        await Self.route(rig, at: later, crossing: false)

        let rows = await rig.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId == reserved.visitId)
        #expect(Int64((rows[0].timestamp.timeIntervalSince1970 * 1000).rounded()) == reservation.occurredAtEpochMilliseconds)
        #expect(rows[0].enteredAt == start)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// Control: only the copy, no later ENTER. Its late second note is still the stay's own
    /// ENTER, so the stay qualifies at 600 with its entry.
    @Test
    func delayedCopyAlone_expectTheStayToQualifyWithItsEntry() async throws {
        let rig = await Self.rig()
        let start = rig.clock.wall
        let first = try await Self.enter(rig, at: start, crossing: true)
        rig.advance(0.2)
        rig.dwell.noteEnter(geofenceId: Self.circle.id, occurredAt: start.addingTimeInterval(0.2), crossing: true)
        rig.advance(599.8)
        await Self.route(rig, at: start.addingTimeInterval(0.2), crossing: true)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        let rows = await rig.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId == first.visitId)
        #expect(rows[0].enteredAt == start)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// Control: the later ENTER with no delayed copy. It ends the old stay, and the new one
    /// qualifies on its own.
    @Test
    func laterEnterInOrder_expectANewStayThatQualifiesOnItsOwn() async throws {
        let rig = await Self.rig()
        let first = try await Self.enter(rig, at: rig.clock.wall, crossing: true)
        rig.advance(600)
        let later = rig.clock.wall
        rig.dwell.noteEnter(geofenceId: Self.circle.id, occurredAt: later, crossing: true)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)
        #expect(await rig.dwellRows().isEmpty)
        await Self.route(rig, at: later, crossing: true)
        rig.advance(600)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        let rows = await rig.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId != first.visitId)
        #expect(rows[0].enteredAt == later)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// The crossing race with the wall clock set between the two ENTERs, and read once by a
    /// revalidation after the step. Both notes are processed after it, so they share a timeline;
    /// the copy's date is from before it. The stay recorded before the step never qualifies at the
    /// later ENTER's fix.
    /// - Forward: the stay the later ENTER begins qualifies with that entry, dated on the clock in
    ///   force when it was noted.
    /// - Backward: the copy's date reads as the future. Its routing starts the stay that continues,
    ///   which reports no entry and counts no wall time until the clock passes that date, so there
    ///   is no DWELL yet. Late, never dated before the step.
    @Test(arguments: [3600.0, -3600.0])
    func delayedCopyAcrossAWallStep_expectTheOldStayNeverQualifies(step: TimeInterval) async throws {
        let rig = await Self.rig()
        let start = rig.clock.wall
        let first = try await Self.enter(rig, at: start, crossing: true)
        rig.advance(0.2)
        rig.dwell.noteEnter(geofenceId: Self.circle.id, occurredAt: start.addingTimeInterval(0.2), crossing: true)
        rig.advance(299.8)
        rig.stepWall(step)
        await rig.dwell.revalidateVisits()
        rig.advance(300)
        let later = rig.clock.wall
        rig.dwell.noteEnter(geofenceId: Self.circle.id, occurredAt: later, crossing: true)
        rig.advance(0.1)
        await Self.route(rig, at: start.addingTimeInterval(0.2), crossing: true)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        #expect(await rig.dwellRows().isEmpty)
        await Self.route(rig, at: later, crossing: true)
        let next = try #require(await rig.storage.getDwellVisit(geofenceId: Self.circle.id))
        #expect(next.visitId != first.visitId)
        rig.advance(600)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        let rows = await rig.dwellRows()
        if step > 0 {
            try #require(rows.count == 1)
            #expect(rows[0].visitId == next.visitId)
            #expect(rows[0].enteredAt == later)
        } else {
            #expect(rows.isEmpty)
            #expect(next.entryObserved == false)
        }
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// Companion through the real binder and resolver: the monitor double delivers the copy and
    /// the later ENTER back to back, before either routing task runs, on a clock that moves on
    /// every read as a real one does. Which task's note lands last is the executor's choice, not
    /// scripted; whatever it is, the old stay must not qualify at the later ENTER.
    @Test
    func copyAndLaterEnterThroughTheBinder_expectTheOldStayNeverQualifies() async throws {
        let rig = await Self.rig()
        let clock = TickingClock(rig.clock)
        let dwell = GeofenceDwellCoordinator(
            storage: rig.storage, transitionEmitter: rig.tracker, contextStore: rig.contextStore, logger: LoggerMock(),
            notificationCenter: NotificationCenter(),
            freshFixProvider: { [weak rig] in rig?.fix(latitudeOffset: 0, accuracy: 10) },
            evidenceRetryDelay: 3600, clock: clock
        )
        let resolver = PolygonMembershipResolver(
            storage: rig.storage, transitionEmitter: rig.tracker, logger: LoggerMock(), contextStore: rig.contextStore,
            dateUtil: rig.dateUtil, notificationCenter: NotificationCenter(), dwellCoordinator: dwell
        )
        let sync = GeofenceSyncCoordinatorMock()
        sync.refreshReturnValue = .success(())
        sync.handleMovementReturnValue = .success(())
        let monitor = MockGeofenceRegionMonitor()
        GeofenceMonitorBinder.bind(monitor: monitor, resolver: resolver, coordinator: sync, logger: LoggerMock(), dwellCoordinator: dwell)

        let start = rig.clock.wall
        monitor.simulateTransition(identifier: Self.circle.id, transition: .enter, location: nil, occurredAt: start)
        await settleQuietly(0.3)
        let first = try #require(await rig.storage.getDwellVisit(geofenceId: Self.circle.id))
        dwell.cancelEvidence(for: Self.circle.id)
        rig.advance(0.2)
        monitor.simulateTransition(identifier: Self.circle.id, transition: .enter, location: nil, occurredAt: rig.clock.wall)
        rig.advance(599.8)
        monitor.simulateTransition(identifier: Self.circle.id, transition: .enter, location: nil, occurredAt: rig.clock.wall)
        await settleQuietly(0.5)
        await dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        #expect(await rig.dwellRows().filter { $0.visitId == first.visitId }.isEmpty)
        dwell.cancelEvidence(for: Self.circle.id)
        withExtendedLifetime(resolver) {}
    }

    /// A manual clock that moves a millisecond on every read, so later processing reads later.
    private final class TickingClock: GeofenceClock, @unchecked Sendable {
        private let clock: ManualGeofenceClock

        init(_ clock: ManualGeofenceClock) {
            self.clock = clock
        }

        func read() -> GeofenceClockReading {
            clock.advance(0.001)
            return clock.read()
        }
    }

    // MARK: - Helpers

    /// Every fix is fresh and inside; a CDP key, so a flush keeps rows in the outbox.
    private static func rig() async -> GeofenceDwellFollowupTests.Rig {
        let rig = await GeofenceDwellFollowupTests.Rig.make(insideFixAlways: true)
        rig.contextStore.setCdpApiKey("test-key")
        await rig.cacheCircle()
        return rig
    }

    /// A native ENTER noted by the binder and routed at once. Its deadline is cancelled: no fix
    /// is asked for until a test asks.
    private static func enter(
        _ rig: GeofenceDwellFollowupTests.Rig, at date: Date, crossing: Bool
    ) async throws -> GeofenceDwellVisit {
        rig.dwell.noteEnter(geofenceId: circle.id, occurredAt: date, crossing: crossing)
        await route(rig, at: date, crossing: crossing)
        let visit = try #require(await rig.storage.getDwellVisit(geofenceId: circle.id))
        rig.dwell.cancelEvidence(for: circle.id)
        return visit
    }

    /// What an ENTER's routing task does for a circle.
    private static func route(_ rig: GeofenceDwellFollowupTests.Rig, at date: Date, crossing: Bool) async {
        await rig.dwell.handleBoundary(
            geofence: circle, transition: .enter, occurredAt: date, expectedUserId: "user-1", entryObserved: crossing
        )
    }
}
