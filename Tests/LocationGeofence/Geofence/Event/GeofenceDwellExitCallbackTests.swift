@testable import CioInternalCommon
@testable import CioLocationGeofence
import CoreLocation
import Foundation
import SharedTests
import Testing

/// A native EXIT reaches the binder synchronously, but is recorded only once its routing task has
/// awaited the resolver's storage read. Until then the binder's note of the callback is all the
/// coordinator knows, and a first DWELL admitted meanwhile would span the departure. The
/// chronology is driven at the coordinator: `noteExitCallback` is the exact call the binder makes
/// in the callback, and the routing is completed later with what the routing task calls —
/// `handleBoundary` for a circle, the resolver's `handleTransition` for a polygon — then
/// `exitCallbackRouted`. Internal chronology, not physical callback acceptance. Storage, tracker,
/// outbox, resolver and fresh fixes are real; only the clock and the fix are scripted, and HTTP
/// fails so every row stays in the outbox.
@Suite("GeofenceDwellExitCallback", .serialized)
@MainActor
struct GeofenceDwellExitCallbackTests {
    /// The follow-up rig's circle: 150 m around (1, 2), dwell after 600 s.
    private static let circle = Geofence(
        id: "circle", latitude: 1, longitude: 2, radius: 150, name: "circle",
        transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1),
        dwellThresholdSeconds: 600
    )

    /// ENTER at 0. At 600 the OS delivers the EXIT and the binder notes it; its routing has not
    /// run. A fresh inside fix at 600.1 must neither queue nor reserve the old stay's DWELL. The
    /// EXIT is then routed and the callback ends; the return's own stay qualifies once.
    @Test
    func exitCallbackNotedBeforeItsRouting_expectNoDwellForTheEndedStay() async throws {
        let rig = await Self.rig()
        let first = try await Self.enter(rig)
        rig.advance(600)
        let exitedAt = rig.clock.wall
        rig.dwell.noteExitCallback(geofenceId: Self.circle.id, occurredAt: exitedAt)
        rig.advance(0.1)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        #expect(await rig.dwellRows().isEmpty)
        let held = await rig.storage.getDwellVisit(geofenceId: Self.circle.id)
        #expect(held?.visitId == first.visitId)
        #expect(held?.dwellReservation == nil)
        await Self.routeExit(rig, at: exitedAt)
        #expect(await rig.storage.getDwellVisit(geofenceId: Self.circle.id) == nil)
        #expect(rig.dwell.pendingExitCallbacks[Self.circle.id] == nil)

        rig.advance(9.9)
        let returnedAt = rig.clock.wall
        let returned = try await Self.enter(rig)
        rig.advance(600)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)
        let rows = await rig.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId == returned.visitId)
        #expect(rows[0].enteredAt == returnedAt)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// Control: a late callback of an EXIT dated before the stay began does not hold it back.
    @Test
    func staleExitCallbackOlderThanTheStay_expectTheStayToQualify() async throws {
        let rig = await Self.rig()
        let stay = try await Self.enter(rig)
        rig.advance(30)
        let staleExit = stay.enteredAt.addingTimeInterval(-30)
        rig.dwell.noteExitCallback(geofenceId: Self.circle.id, occurredAt: staleExit)
        rig.advance(570)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        #expect(await rig.dwellRows().map(\.visitId) == [stay.visitId])
        await Self.routeExit(rig, at: staleExit)
        #expect(await rig.storage.getDwellVisit(geofenceId: Self.circle.id)?.visitId == stay.visitId)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// Control: a dwell reserved before the callback is delivered as reserved while it is pending.
    @Test
    func dwellReservedBeforeTheCallback_expectDeliveredAsReserved() async throws {
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
        rig.dwell.noteExitCallback(geofenceId: Self.circle.id, occurredAt: exitedAt)
        rig.advance(0.1)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        let rows = await rig.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId == reserved.visitId)
        #expect(Int64((rows[0].timestamp.timeIntervalSince1970 * 1000).rounded()) == reservation.occurredAtEpochMilliseconds)
        #expect(rows[0].enteredAt == start)
        #expect(rows[0].dwellDurationSeconds == 600)
        await Self.routeExit(rig, at: exitedAt)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// Control: a stay whose dwell went out is untouched by a pending callback — same id, flags
    /// and reservation, no new row — until its EXIT is routed.
    @Test
    func emittedStayUnderAPendingCallback_expectUnchanged() async throws {
        let rig = await Self.rig()
        _ = try await Self.enter(rig)
        rig.advance(600)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)
        let emitted = try #require(await rig.storage.getDwellVisit(geofenceId: Self.circle.id))
        try #require(emitted.emitted)
        rig.advance(60)
        let exitedAt = rig.clock.wall
        rig.dwell.noteExitCallback(geofenceId: Self.circle.id, occurredAt: exitedAt)
        rig.advance(0.1)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        #expect(await rig.storage.getDwellVisit(geofenceId: Self.circle.id) == emitted)
        #expect(await rig.dwellRows().map(\.visitId) == [emitted.visitId])
        await Self.routeExit(rig, at: exitedAt)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// The wall clock is set an hour either way during the stay, and the callback is dated on
    /// the new clock. Its date cannot be ordered against the entry, so it holds the DWELL back by
    /// processing order.
    @Test(arguments: [3600.0, -3600.0])
    func exitCallbackAcrossAWallStep_expectNoDwellForTheStay(step: TimeInterval) async throws {
        let rig = await Self.rig()
        _ = try await Self.enter(rig)
        rig.advance(300)
        rig.stepWall(step)
        rig.advance(300)
        let exitedAt = rig.clock.wall
        rig.dwell.noteExitCallback(geofenceId: Self.circle.id, occurredAt: exitedAt)
        rig.advance(0.1)
        await rig.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        #expect(await rig.dwellRows().isEmpty)
        #expect(await rig.storage.getDwellVisit(geofenceId: Self.circle.id)?.dwellReservation == nil)
        await Self.routeExit(rig, at: exitedAt)
        #expect(await rig.storage.getDwellVisit(geofenceId: Self.circle.id) == nil)
        rig.dwell.cancelEvidence(for: Self.circle.id)
    }

    /// A polygon's covering circle reports an EXIT; the resolver's pass meanwhile still finds the
    /// device inside the shape. The pending callback defers the first DWELL, and records no EXIT:
    /// the visit stays. The resolver then routes the EXIT and decides nothing (its circle has
    /// expired); once the callback ends, the next fresh proof qualifies the same visit, once.
    @Test
    func undecidedCoveringExitCallback_expectTheDwellDeferredNotLost() async throws {
        let device = BootAmbiguityDevice()
        let process = await BootAmbiguityProcess(device: device)
        let polygon = BootAmbiguityDevice.polygon
        await process.pass()
        let stay = try #require(await process.visit())
        device.advance(600)
        let exitedAt = device.clock.wall
        process.dwell.noteExitCallback(geofenceId: polygon.id, occurredAt: exitedAt)
        device.advance(0.1)
        await process.pass()

        #expect(await process.dwellRows().isEmpty)
        #expect(await process.visit() == stay)
        #expect(process.dwell.exitMarks[polygon.id] == nil)
        await process.resolver.handleTransition(
            identifier: polygon.id, transition: .exit, occurredAt: exitedAt, eventCircle: .expired,
            receivedForUserId: "user-a"
        )
        process.dwell.exitCallbackRouted(geofenceId: polygon.id, occurredAt: exitedAt)
        #expect(process.dwell.exitMarks[polygon.id] == nil)
        device.advance(1)
        await process.pass()
        device.advance(600)
        await process.pass()

        #expect(await process.dwellRows().map(\.visitId) == [stay.visitId])
        #expect(await process.visit()?.emitted == true)
        process.end()
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

    /// What the binder's routing task does for a circle EXIT, then its callback's end.
    private static func routeExit(_ rig: GeofenceDwellFollowupTests.Rig, at date: Date) async {
        await rig.dwell.handleBoundary(geofence: circle, transition: .exit, occurredAt: date, expectedUserId: "user-1")
        rig.dwell.exitCallbackRouted(geofenceId: circle.id, occurredAt: date)
    }
}
