@testable import CioInternalCommon
@testable import CioLocationGeofence
import CoreLocation
import Foundation
import SharedTests
import Testing

/// An EXIT, or decisive outside proof, is recorded before its first await; the visit it ends is
/// removed only after storage hops. A first DWELL admitted in between would span a departure the
/// coordinator already knows. The chronology is driven at the coordinator: `recordExit` with a
/// mark built as `handleBoundary` and `endContinuity` build theirs is the exact synchronous prefix
/// of that EXIT or proof, and the rest of the same event is completed afterwards. Storage, tracker,
/// outbox and the fresh circle fix are real (`GeofenceDwellFollowupTests.Rig`); only the clock and
/// the fix are scripted, and HTTP fails so every row stays in the outbox.
@Suite("GeofenceDwellKnownExitAdmission", .serialized)
@MainActor
struct GeofenceDwellKnownExitAdmissionTests {
    /// The rig's circle: 150 m around (1, 2), dwell after 600 s.
    private static let circle = Geofence(
        id: "circle", latitude: 1, longitude: 2, radius: 150, name: "circle",
        transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1),
        dwellThresholdSeconds: 600
    )

    /// ENTER at 0; the EXIT at 600 is recorded but not yet applied; a fresh inside fix at 600.1
    /// must not queue the old stay's first DWELL. The same EXIT then completes, and the return's
    /// own stay qualifies once, after its own 600 s.
    @Test
    func exitRecordedBeforeTheFirstAdmission_expectNoDwellForTheEndedStay() async throws {
        let rig = await Self.rig()
        let first = try await Self.enter(rig)
        rig.advance(600)
        let exitedAt = rig.clock.wall
        rig.dwell.recordExit(GeofenceExitMark(date: exitedAt, processedAt: rig.dwell.readClock(), source: .exitEvent), geofenceId: Self.circle.id)
        rig.advance(0.1)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        #expect(await rig.dwellRows().isEmpty)
        // Not even reserved: a reservation is delivered as is by any later process.
        #expect(await rig.storage.getDwellVisit(geofenceId: Self.circle.id)?.dwellReservation == nil)
        await rig.dwell.handleBoundary(geofence: Self.circle, transition: .exit, occurredAt: exitedAt)
        #expect(await rig.storage.getDwellVisit(geofenceId: Self.circle.id) == nil)
        try await Self.returnQualifiesOnce(rig, after: first)
    }

    /// The same with decisive outside proof: a fresh fix wholly outside, recorded as
    /// `endContinuity` does before its removal, then an inside fix 0.1 s later. The same proof
    /// then completes through the resolver-pass entry point.
    @Test
    func outsideProofRecordedBeforeTheFirstAdmission_expectNoDwellForTheEndedStay() async throws {
        let rig = await Self.rig()
        let first = try await Self.enter(rig)
        rig.advance(600)
        let outside = rig.fix(latitudeOffset: 0.01, accuracy: 10)
        rig.dwell.recordExit(GeofenceExitMark(date: outside.timestamp, processedAt: rig.dwell.readClock(), source: .outsideEvidence), geofenceId: Self.circle.id)
        rig.advance(0.1)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        #expect(await rig.dwellRows().isEmpty)
        // Not even reserved: a reservation is delivered as is by any later process.
        #expect(await rig.storage.getDwellVisit(geofenceId: Self.circle.id)?.dwellReservation == nil)
        await rig.dwell.recordOutsideEvidence(fix: outside, expectedUserId: "user-1")
        #expect(await rig.storage.getDwellVisit(geofenceId: Self.circle.id) == nil)
        try await Self.returnQualifiesOnce(rig, after: first)
    }

    /// Control: a late copy of an EXIT dated before a newer stay began does not end that stay, and
    /// does not block its DWELL.
    @Test
    func staleExitOlderThanTheStay_expectTheStayToQualify() async throws {
        let rig = await Self.rig()
        let stay = try await Self.enter(rig)
        rig.advance(30)
        let staleExit = stay.enteredAt.addingTimeInterval(-30)
        rig.dwell.recordExit(GeofenceExitMark(date: staleExit, processedAt: rig.dwell.readClock(), source: .exitEvent), geofenceId: Self.circle.id)
        await rig.dwell.handleBoundary(geofence: Self.circle, transition: .exit, occurredAt: staleExit)
        rig.advance(570)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        let rows = await rig.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId == stay.visitId)
        #expect(rows[0].enteredAt == stay.enteredAt)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// Control: a dwell reserved before the EXIT is a fact about the stay before it. It is
    /// delivered as reserved, with its millisecond timestamp, entry and duration, then the EXIT
    /// ends the visit.
    @Test
    func dwellReservedBeforeTheExit_expectDeliveredAsReserved() async throws {
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
        let exitedAt = rig.clock.wall
        rig.dwell.recordExit(GeofenceExitMark(date: exitedAt, processedAt: rig.dwell.readClock(), source: .exitEvent), geofenceId: Self.circle.id)
        rig.advance(0.1)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)
        await rig.dwell.handleBoundary(geofence: Self.circle, transition: .exit, occurredAt: exitedAt)

        let rows = await rig.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId == reserved.visitId)
        #expect(Int64((rows[0].timestamp.timeIntervalSince1970 * 1000).rounded()) == reservation.occurredAtEpochMilliseconds)
        #expect(rows[0].enteredAt == start)
        #expect(rows[0].dwellDurationSeconds == 600)
        #expect(await rig.storage.getDwellVisit(geofenceId: Self.circle.id) == nil)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// The wall clock is set an hour either way during the stay, and the EXIT is dated on the new
    /// clock. Its date cannot be ordered against the entry, so it is taken as ending the stay by
    /// processing order: the fix 0.1 s later queues no DWELL.
    @Test(arguments: [3600.0, -3600.0])
    func exitRecordedAcrossAWallStep_expectNoDwellForTheStay(step: TimeInterval) async throws {
        let rig = await Self.rig()
        _ = try await Self.enter(rig)
        rig.advance(300)
        rig.stepWall(step)
        rig.advance(300)
        let exitedAt = rig.clock.wall
        rig.dwell.recordExit(GeofenceExitMark(date: exitedAt, processedAt: rig.dwell.readClock(), source: .exitEvent), geofenceId: Self.circle.id)
        rig.advance(0.1)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        #expect(await rig.dwellRows().isEmpty)
        // Not even reserved: a reservation is delivered as is by any later process.
        #expect(await rig.storage.getDwellVisit(geofenceId: Self.circle.id)?.dwellReservation == nil)
        await rig.dwell.handleBoundary(geofence: Self.circle, transition: .exit, occurredAt: exitedAt)
        #expect(await rig.storage.getDwellVisit(geofenceId: Self.circle.id) == nil)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    // MARK: - Helpers

    /// Every fix is fresh and inside; a CDP key, so a flush keeps rows in the outbox.
    private static func rig() async -> GeofenceDwellFollowupTests.Rig {
        let rig = await GeofenceDwellFollowupTests.Rig.make(insideFixAlways: true)
        rig.contextStore.setCdpApiKey("test-key")
        await rig.cacheCircle()
        return rig
    }

    /// A native ENTER now. Its deadline is cancelled: no fix is asked for until a test asks.
    private static func enter(_ rig: GeofenceDwellFollowupTests.Rig) async throws -> GeofenceDwellVisit {
        await rig.dwell.handleBoundary(geofence: circle, transition: .enter, occurredAt: rig.clock.wall)
        let visit = try #require(await rig.storage.getDwellVisit(geofenceId: circle.id))
        rig.dwell.cancelEvidence(for: circle.id)
        return visit
    }

    /// The device comes back 10 s after the EXIT: that ENTER's stay qualifies after its own
    /// 600 s, once. On a whole second, as the outbox keeps milliseconds.
    private static func returnQualifiesOnce(
        _ rig: GeofenceDwellFollowupTests.Rig, after first: GeofenceDwellVisit
    ) async throws {
        rig.advance(9.9)
        let returnedAt = rig.clock.wall
        let returned = try await enter(rig)
        #expect(returned.visitId != first.visitId)
        rig.advance(600)
        await rig.dwell.requestQualifyingEvidence(geofenceId: circle.id)
        await rig.dwell.requestQualifyingEvidence(geofenceId: circle.id)

        let rows = await rig.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId == returned.visitId)
        #expect(rows[0].enteredAt == returnedAt)
        rig.dwell.cancelEvidence(for: circle.id)
    }
}
