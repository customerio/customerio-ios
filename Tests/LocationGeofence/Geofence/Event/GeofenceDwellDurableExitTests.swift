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

/// `CLMonitor` writes an observed circle EXIT to disk before it hands the event to the binder. A
/// process dying between that write and the visit's removal used to leave the visit open across
/// the departure, so a later fresh fix qualified its first DWELL. The write now closes the visit
/// in the same storage write. Each test runs the real `CLMonitor` wrapper (only CoreLocation is
/// faked) over real files; a process "dies" by never routing the event it was handed, and the next
/// is a fresh set of objects over the same files. Internal chronology on a scripted clock, not
/// physical relaunch acceptance.
@Suite("GeofenceDwellDurableExit", .serialized, .enabled(if: monitorAvailable))
@MainActor
struct GeofenceDwellDurableExitTests {
    private static let circle = DurableExitFences.circle

    /// EXIT recorded at 600, then death. The next process's fresh inside fix queues and reserves
    /// nothing for the old stay, and asks for no fix for it. The next ENTER `CLMonitor` records and
    /// the binder routes starts the return's own stay, which qualifies once after its own 600 s.
    @Test
    @available(iOS 17.0, *)
    func exitRecordedThenDeath_expectNoDwellForTheEndedStay() async throws {
        let device = DurableExitDevice()
        let first = await DurableExitProcess(device: device)
        let stay = try await Self.startStay(first)
        device.advance(600)
        let exitedAt = device.clock.wall
        await first.deliver(.unsatisfied)
        #expect(await first.visit()?.closedByObservedBoundary == exitedAt)
        first.end()
        device.advance(60)

        let second = await DurableExitProcess(device: device)
        await second.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)
        #expect(device.fixesRequested == 0)
        await second.freshInsideEvidence()
        #expect(await second.dwellRows().isEmpty)
        #expect(await second.visit()?.dwellReservation == nil)
        try await Self.returnQualifiesOnce(second, device: device, after: stay, exitFirst: false)
    }

    /// EXIT then the return's crossing ENTER recorded, neither routed, then death: the monitor's
    /// record now reads inside. The old stay still queues nothing; the next routed pair starts a
    /// stay of its own.
    @Test
    @available(iOS 17.0, *)
    func exitAndReturnRecordedThenDeath_expectNoDwellForTheEndedStay() async throws {
        let device = DurableExitDevice()
        let first = await DurableExitProcess(device: device)
        let stay = try await Self.startStay(first)
        device.advance(600)
        let exitedAt = device.clock.wall
        await first.deliver(.unsatisfied)
        device.advance(30)
        await first.deliver(.satisfied)
        #expect(await first.storage.getMonitorRegionRecords()[Self.circle.id]?.lastState == .enter)
        #expect(await first.visit()?.closedByObservedBoundary == exitedAt)
        first.end()
        device.advance(60)

        let second = await DurableExitProcess(device: device)
        await second.freshInsideEvidence()
        #expect(await second.dwellRows().isEmpty)
        #expect(await second.visit()?.dwellReservation == nil)
        try await Self.returnQualifiesOnce(second, device: device, after: stay, exitFirst: true)
    }

    /// After the closed stay, a discovery ENTER (the sync's, nothing proved current) does not adopt
    /// it: it starts a candidate of its own, which qualifies 600 s after its first fresh proof.
    @Test
    @available(iOS 17.0, *)
    func discoveryAfterAClosedStay_expectAStayOfItsOwn() async throws {
        let device = DurableExitDevice()
        let first = await DurableExitProcess(device: device)
        let stay = try await Self.startStay(first)
        device.advance(600)
        await first.deliver(.unsatisfied)
        first.end()
        device.advance(60)

        let second = await DurableExitProcess(device: device)
        await second.dwell.handleBoundary(
            geofence: Self.circle, transition: .enter, occurredAt: device.clock.wall, crossingObserved: false, presenceProven: false
        )
        #expect(await second.visit()?.visitId != stay.visitId)
        await second.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)
        device.advance(600)
        await second.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)

        let rows = await second.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId != stay.visitId)
        #expect(rows[0].enteredAt == nil)
        second.end()
    }

    /// Control: a late EXIT dated before a newer stay began — that stay recorded by the coordinator
    /// directly, as discovery then proof would — does not close it, and the stay qualifies.
    @Test
    @available(iOS 17.0, *)
    func staleExitOlderThanANewerStay_expectNotClosed() async throws {
        let device = DurableExitDevice()
        let process = await DurableExitProcess(device: device)
        await process.register(seenAt: device.fix())
        // Clear of the registration's 10 s replay window, so the EXIT reaches the record.
        device.advance(30)
        let enteredAt = device.clock.wall
        await process.dwell.handleBoundary(geofence: Self.circle, transition: .enter, occurredAt: enteredAt)
        process.dwell.cancelEvidence(for: Self.circle.id)
        device.advance(30)
        let exitedAt = enteredAt.addingTimeInterval(-10)
        await process.deliver(.unsatisfied, at: exitedAt)

        let record = await process.storage.getMonitorRegionRecords()[Self.circle.id]
        #expect(record?.lastState == .exit)
        #expect(record?.lastEventDate == exitedAt)
        let stay = try #require(await process.visit())
        #expect(stay.closedByObservedBoundary == nil)
        device.advance(570)
        await process.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)
        #expect(await process.dwellRows().map(\.visitId) == [stay.visitId])
        process.end()
    }

    /// Control: a polygon's covering circle reports inside then outside. Its EXIT proves nothing
    /// about the shape, so the polygon's visit is not closed.
    @Test
    @available(iOS 17.0, *)
    func coveringCircleExit_expectThePolygonVisitNotClosed() async throws {
        let device = DurableExitDevice()
        let process = await DurableExitProcess(device: device)
        let polygon = DurableExitFences.polygon
        await process.register(polygon)
        let visit = GeofenceDwellVisit(
            visitId: UUID().uuidString, enteredAt: device.clock.wall, geometryRevision: polygon.dwellRevision,
            userId: "user-a", emitted: false, entryObserved: false, dwellReservation: nil,
            timing: GeofenceVisitTiming(enteredAt: device.clock.wall, recordedAt: device.clock.read())
        )
        try #require(await process.storage.saveDwellVisit(visit, geofenceId: polygon.id))
        device.advance(30)
        await process.deliver(.satisfied, to: polygon.id)
        device.advance(600)
        await process.deliver(.unsatisfied, to: polygon.id)

        #expect(await process.storage.getMonitorRegionRecords()[polygon.id]?.lastState == .exit)
        #expect(await process.visit(polygon) == visit)
        process.end()
    }

    /// Control: `CLMonitor` correcting the outside state it assumed at registration is no crossing:
    /// an emitted or reserved stay is not closed, and is unchanged.
    @Test(arguments: [false, true])
    @available(iOS 17.0, *)
    func correctionOfAnAssumedState_expectNoClosure(reserved: Bool) async throws {
        let device = DurableExitDevice()
        let process = await DurableExitProcess(device: device)
        await process.register()
        let qualified = try await Self.qualifiedStay(process, device: device, reserved: reserved)
        device.advance(30)
        await process.deliver(.satisfied)

        #expect(await process.visit() == qualified)
        process.end()
    }

    /// An observed crossing ENTER the SDK never routed — `CLMonitor` had seen the device outside —
    /// closes the stay recorded before it, as the start of a new interval would.
    @Test
    @available(iOS 17.0, *)
    func crossingEnterRecordedThenDeath_expectTheOlderStayClosed() async throws {
        let device = DurableExitDevice()
        let first = await DurableExitProcess(device: device)
        await first.register(seenAt: device.fix(latitudeOffset: 0.01))
        await first.dwell.handleBoundary(geofence: Self.circle, transition: .enter, occurredAt: device.clock.wall)
        first.dwell.cancelEvidence(for: Self.circle.id)
        device.advance(600)
        let crossedAt = device.clock.wall
        await first.deliver(.satisfied)
        #expect(await first.visit()?.closedByObservedBoundary == crossedAt)
        first.end()
        device.advance(60)

        let second = await DurableExitProcess(device: device)
        await second.freshInsideEvidence()
        #expect(await second.dwellRows().isEmpty)
        second.end()
    }

    /// The wall clock is set an hour either way during the stay, and the EXIT is dated on the new
    /// clock. Its date cannot be ordered against the entry, so it closes the stay by processing
    /// order: no DWELL after death.
    @Test(arguments: [3600.0, -3600.0])
    @available(iOS 17.0, *)
    func exitRecordedAcrossAWallStep_expectTheStayClosed(step: TimeInterval) async throws {
        let device = DurableExitDevice()
        let first = await DurableExitProcess(device: device)
        _ = try await Self.startStay(first)
        device.advance(3600)
        device.stepWall(step)
        device.advance(3600)
        let exitedAt = device.clock.wall
        await first.deliver(.unsatisfied)
        #expect(await first.visit()?.closedByObservedBoundary == exitedAt)
        first.end()
        device.advance(60)

        let second = await DurableExitProcess(device: device)
        await second.freshInsideEvidence()
        #expect(await second.dwellRows().isEmpty)
        #expect(await second.visit()?.dwellReservation == nil)
        second.end()
    }

    /// Control: a dwell reserved before the EXIT is a fact about the stay before it. The closure
    /// leaves it as is, and the next process delivers it as reserved, once.
    @Test
    @available(iOS 17.0, *)
    func dwellReservedBeforeADurableExit_expectDeliveredAsReserved() async throws {
        let device = DurableExitDevice()
        let first = await DurableExitProcess(device: device)
        await first.register(seenAt: device.fix())
        let reserved = try await Self.qualifiedStay(first, device: device, reserved: true)
        let reservation = try #require(reserved.dwellReservation)
        device.advance(100)
        await first.deliver(.unsatisfied)
        #expect(await first.visit()?.dwellReservation == reservation)
        first.end()
        device.advance(60)

        let second = await DurableExitProcess(device: device)
        await second.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)
        await second.freshInsideEvidence()

        let rows = await second.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId == reserved.visitId)
        #expect(Int64((rows[0].timestamp.timeIntervalSince1970 * 1000).rounded()) == reservation.occurredAtEpochMilliseconds)
        #expect(rows[0].enteredAt == reservation.enteredAt)
        second.end()
    }

    // MARK: - Helpers

    /// Registers the circle with its state assumed outside and routes `CLMonitor`'s correction
    /// ENTER, which starts the stay; from then on the process dies at the next event.
    @available(iOS 17.0, *)
    private static func startStay(_ process: DurableExitProcess) async throws -> GeofenceDwellVisit {
        process.route()
        await process.register()
        await process.deliver(.satisfied)
        let stay = try #require(await process.visit())
        process.dwell.cancelEvidence(for: circle.id)
        process.dieOnNextEvent()
        return stay
    }

    /// A stay entered now and qualified 600 s later: emitted through a fresh fix, or reserved and
    /// queued no further, as a crash before the outbox write leaves it.
    @available(iOS 17.0, *)
    private static func qualifiedStay(
        _ process: DurableExitProcess, device: DurableExitDevice, reserved: Bool
    ) async throws -> GeofenceDwellVisit {
        await process.dwell.handleBoundary(geofence: circle, transition: .enter, occurredAt: device.clock.wall)
        let stay = try #require(await process.visit())
        process.dwell.cancelEvidence(for: circle.id)
        device.advance(600)
        if reserved {
            let reservation = GeofenceDwellReservation(
                occurredAtEpochMilliseconds: Int64((device.clock.wall.timeIntervalSince1970 * 1000).rounded()),
                enteredAtEpochMilliseconds: nil, durationSeconds: nil, thresholdSeconds: 600,
                detectionSource: "location_evidence"
            )
            guard case .reserved = await process.storage.reserveDwellEmission(reservation, for: stay, geofenceId: circle.id) else {
                Issue.record("not reserved")
                return stay
            }
        } else {
            await process.dwell.requestQualifyingEvidence(geofenceId: circle.id)
        }
        process.dwell.cancelEvidence(for: circle.id)
        return try #require(await process.visit())
    }

    /// The return through the binder: `CLMonitor` records the next EXIT (if the record reads
    /// inside) and ENTER and the binder routes them. That stay qualifies once, with its own entry.
    @available(iOS 17.0, *)
    private static func returnQualifiesOnce(
        _ process: DurableExitProcess, device: DurableExitDevice, after stay: GeofenceDwellVisit, exitFirst: Bool
    ) async throws {
        process.route()
        await process.register()
        if exitFirst {
            await process.deliver(.unsatisfied)
            device.advance(10)
        }
        let returnedAt = device.clock.wall
        await process.deliver(.satisfied)
        let returned = try #require(await process.visit())
        #expect(returned.visitId != stay.visitId)
        device.advance(600)
        await process.dwell.requestQualifyingEvidence(geofenceId: circle.id)

        let rows = await process.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId == returned.visitId)
        #expect(rows[0].enteredAt == returnedAt)
        process.end()
    }
}
