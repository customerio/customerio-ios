@testable import CioInternalCommon
@testable import CioLocationGeofence
import CoreLocation
import Foundation
import SharedTests
import Testing

private let monitorAvailable: Bool = {
    if #available(iOS 17.0, *) { return true }
    return false
}()

/// An EXIT that proves nothing about the stay it would end carries no duration, and leaves the
/// stay to be timed by its own EXIT: one raised by a replaced generation of the circle, or one a
/// baseline heal synthesized. Each test runs the real `CLMonitor` wrapper (only CoreLocation is
/// faked), binder, resolver and dwell coordinator over the real `GeofenceStorage` file and file
/// outbox; HTTP fails, so rows stay. A process "dies" by never routing the event it was handed; the
/// next is fresh objects over the same files. Scripted clock; not physical callback acceptance.
@Suite("GeofenceExitDurationStaleGeneration", .serialized, .enabled(if: monitorAvailable))
@MainActor
struct ExitDurationStaleGenerationTests {
    private static let circle = DurableExitFences.circle

    // MARK: - A replaced generation's EXIT

    /// An observed stay in the 150 m circle went out (or was reserved). The circle is re-registered
    /// under a 100 m cap; the new install has written its record and is parked at the OS, so the
    /// 150 m circle the stay was entered by still raises events, now `.expired`. Its EXIT is
    /// delivered, untimed. The stay keeps its id, flags and reservation; no EXIT mark or callback
    /// barrier is left; a fresh inside fix past the threshold queues no second DWELL. Once the
    /// install is confirmed, the current circle's own EXIT times the stay.
    @Test(arguments: [true, false])
    @available(iOS 17.0, *)
    func replacedCircleExitOverAQualifiedStay_expectUntimedThenTheOwnExitTimesIt(emitted: Bool) async throws {
        let device = DurableExitDevice()
        let process = await DurableExitProcess(device: device)
        process.route()
        let stay = try await Self.qualifiedStay(process, device: device, emitted: emitted)
        let dwellRowsBefore = await process.dwellRows().count

        let record = try await Self.reregisterUnderACapParkedAtTheOS(process, device: device)
        device.advance(40)
        await process.deliver(.unsatisfied)

        let staleRow = try #require(await Self.exitRows(process).last)
        #expect(await Self.exitRows(process).count == 1)
        #expect(staleRow.visitId == nil)
        #expect(staleRow.enteredAt == nil)
        #expect(staleRow.visitDurationSeconds == nil)
        let kept = try #require(await process.visit())
        #expect(kept.visitId == stay.visitId)
        #expect(kept.timing == stay.timing)
        #expect(kept.dwellReservation == stay.dwellReservation)
        #expect(kept.closedByObservedBoundary == nil)
        // A reserved dwell may meanwhile have gone out, as reserved; an emitted stay is unchanged.
        #expect(!emitted || kept == stay)
        #expect(await process.storage.getMonitorRegionRecords()[Self.circle.id] == record)
        #expect(process.dwell.exitMarks[Self.circle.id] == nil)
        Self.expectNoExitBarrier(process.dwell)

        device.advance(600)
        await process.freshInsideEvidence()
        process.dwell.cancelEvidence(for: Self.circle.id)
        let dwellVisitIds = await process.dwellRows().map(\.visitId)
        #expect(dwellVisitIds.count == max(dwellRowsBefore, 1))
        #expect(dwellVisitIds.allSatisfy { $0 == stay.visitId })

        process.os.releaseOperations()
        await settleQuietly(0.3)
        // Past the public EXIT cooldown the stale EXIT's row started; within it the EXIT below would
        // still end the stay, but its row would be suppressed.
        device.advance(GeofenceConstants.eventCooldownInterval - 600 + 60)
        let exitedAt = device.clock.wall
        await process.deliver(.unsatisfied, at: exitedAt)

        let ownRow = try #require(await Self.exitRows(process).last)
        #expect(await Self.exitRows(process).count == 2)
        #expect(ownRow.visitId == stay.visitId)
        #expect(ownRow.visitDurationSeconds == Int(exitedAt.timeIntervalSince1970) - Int(stay.enteredAt.timeIntervalSince1970))
        #expect(await process.visit() == nil)
        Self.expectNoExitBarrier(process.dwell)
        process.end()
    }

    // MARK: - A healed EXIT

    /// An observed stay; 600 s later a sync's heal sees a fix settled 1.1 km outside and the EXIT
    /// it synthesizes is routed. The fix only dates when the departure was noticed: the EXIT is
    /// delivered untimed and ends the stay, so a fresh inside fix queues no DWELL for it.
    @Test(arguments: [100000.0, 100.0])
    @available(iOS 17.0, *)
    func healedExitRouted_expectUntimedAndTheStayEnded(cap: Double) async throws {
        let device = DurableExitDevice()
        let process = await DurableExitProcess(device: device)
        process.authority.maximumRegionMonitoringDistance = cap
        process.route()
        let stay = try await Self.observedStay(process, device: device)
        device.advance(600)
        await process.heal(Self.circle, seeing: device.fix(latitudeOffset: 0.01), until: .exit)

        let row = try #require(await Self.exitRows(process).last)
        #expect(await Self.exitRows(process).count == 1)
        #expect(row.visitId == nil)
        #expect(row.enteredAt == nil)
        #expect(row.visitDurationSeconds == nil)
        #expect(await process.visit()?.visitId != stay.visitId)
        Self.expectNoExitBarrier(process.dwell)
        await process.freshInsideEvidence()
        #expect(await process.dwellRows().isEmpty)
        process.end()
    }

    /// The heal's EXIT is recorded, closing the stay in that write, and the process dies before
    /// routing it. The next process's fresh inside fix queues and reserves nothing for the old stay;
    /// the device's next real crossing starts a new stay, and that stay's own EXIT times it alone.
    @Test
    @available(iOS 17.0, *)
    func healedExitThenDeath_expectTheNextStayTimedFromItsOwnEntry() async throws {
        let device = DurableExitDevice()
        let first = await DurableExitProcess(device: device)
        first.route()
        let stay = try await Self.observedStay(first, device: device)
        first.dieOnNextEvent()
        device.advance(600)
        await first.heal(Self.circle, seeing: device.fix(latitudeOffset: 0.01), until: .exit)
        #expect(await first.visit()?.closedByObservedBoundary != nil)
        first.end()
        device.advance(60)

        let second = await DurableExitProcess(device: device)
        second.route()
        await second.freshInsideEvidence()
        second.dwell.cancelEvidence(for: Self.circle.id)
        #expect(await second.dwellRows().isEmpty)
        #expect(await second.visit()?.dwellReservation == nil)
        await second.deliver(.satisfied)
        let next = try #require(await second.visit())
        second.dwell.cancelEvidence(for: Self.circle.id)
        #expect(next.visitId != stay.visitId)
        #expect(next.entryObserved)
        device.advance(300)
        await second.deliver(.unsatisfied)

        let row = try #require(await Self.exitRows(second).last)
        #expect(await Self.exitRows(second).count == 1)
        #expect(row.visitId == next.visitId)
        #expect(row.visitDurationSeconds == 300)
        second.end()
    }

    // MARK: - Helpers

    /// Registered from a fix outside it, so the satisfied event is an observed crossing.
    @available(iOS 17.0, *)
    private static func observedStay(_ process: DurableExitProcess, device: DurableExitDevice) async throws -> GeofenceDwellVisit {
        await process.register(seenAt: device.fix(latitudeOffset: 0.01))
        await process.deliver(.satisfied)
        let stay = try #require(await process.visit())
        try #require(stay.entryObserved)
        process.dwell.cancelEvidence(for: circle.id)
        return stay
    }

    /// Re-registers the circle, seen from inside, under a 100 m cap: the new install writes its
    /// 100 m record and is parked at the OS, which still holds the 150 m circle. Returns the record.
    @available(iOS 17.0, *)
    private static func reregisterUnderACapParkedAtTheOS(
        _ process: DurableExitProcess, device: DurableExitDevice
    ) async throws -> MonitorRegionRecord {
        process.os.holdOperations()
        process.authority.maximumRegionMonitoringDistance = 100
        process.authority.answerCachedLocation = { [device] in device.fix() }
        process.monitor.startMonitoring(
            identifier: circle.id, center: LocationData(latitude: 1, longitude: 2), radius: 150, transitionTypes: [.enter, .exit]
        )
        for _ in 0 ..< 200 where await process.storage.getMonitorRegionRecords()[circle.id]?.radius != 100 {
            try? await Task.sleep(nanoseconds: 10000000)
        }
        process.authority.answerCachedLocation = nil
        let record = try #require(await process.storage.getMonitorRegionRecords()[circle.id])
        try #require(record.radius == 100)
        try #require(process.os.held[circle.id]?.radius == 150)
        return record
    }

    /// An observed stay qualified 600 s after its entry: emitted through fresh inside evidence, or
    /// reserved and never queued, as an outbox write that failed leaves it.
    @available(iOS 17.0, *)
    private static func qualifiedStay(
        _ process: DurableExitProcess, device: DurableExitDevice, emitted: Bool
    ) async throws -> GeofenceDwellVisit {
        let stay = try await observedStay(process, device: device)
        device.advance(600)
        if emitted {
            await process.dwell.recordInsideEvidence(geofence: circle, at: device.clock.wall, source: "location_evidence")
            try #require(await process.dwellRows().count == 1)
        } else {
            let reservation = GeofenceDwellReservation(
                occurredAtEpochMilliseconds: Int64((device.clock.wall.timeIntervalSince1970 * 1000).rounded()),
                enteredAtEpochMilliseconds: Int64((stay.enteredAt.timeIntervalSince1970 * 1000).rounded()),
                durationSeconds: 600, thresholdSeconds: 600, detectionSource: "location_evidence"
            )
            try #require(await process.storage.reserveDwellEmission(reservation, for: stay, geofenceId: circle.id) == .reserved(reservation))
        }
        process.dwell.cancelEvidence(for: circle.id)
        let qualified = try #require(await process.visit())
        try #require(qualified.emitted == emitted)
        return qualified
    }

    /// No EXIT callback or routing is still counted, and no EXIT's view of the ENTERs outlives the
    /// EXIT mark it belongs to: with no mark held, nothing is left.
    private static func expectNoExitBarrier(_ dwell: GeofenceDwellCoordinator) {
        #expect(dwell.pendingExitCallbacks[circle.id] == nil)
        #expect(dwell.exitDuration.routingsInFlight[circle.id] == nil)
        #expect(!dwell.exitDuration.visitsEndedByPendingExit.keys.contains(circle.id))
        let markedExits = Set((dwell.exitMarks[circle.id] ?? []).filter { $0.source == .exitEvent }.map(\.date))
        #expect(Set(dwell.exitDuration.entersKnownAtExit[circle.id].map { Array($0.keys) } ?? []).isSubset(of: markedExits))
    }

    @available(iOS 17.0, *)
    private static func exitRows(_ process: DurableExitProcess) async -> [PendingGeofenceMetric] {
        await process.outbox.rows().filter { $0.transition == .exit }.sorted { $0.timestamp < $1.timestamp }
    }
}
