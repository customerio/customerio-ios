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

/// A visit `CLMonitor` closed in the same storage write as its observed EXIT or crossing ENTER may be
/// timed only by that exact EXIT: the one whose original OS date the closure holds. Each test runs
/// the real `CLMonitor` wrapper (only CoreLocation is faked) over the real `GeofenceStorage` file
/// and file outbox, with the dwell coordinator, resolver and binder; HTTP fails, so rows stay. A
/// process "dies" by never routing the event it was handed; the next is fresh objects over the same
/// files. Scripted clock; not physical relaunch or callback acceptance.
@Suite("GeofenceExitDurationObservedBoundary", .serialized, .enabled(if: monitorAvailable))
@MainActor
struct ExitDurationObservedBoundaryTests {
    private static let circle = DurableExitFences.circle
    /// EXIT-only, dwell disabled: its visits exist only to time the EXIT.
    private static let exitOnly = Geofence(
        id: "exit-only", latitude: 3, longitude: 4, radius: 150, name: "exit-only",
        transitionTypes: [.exit], lastUpdated: Date(timeIntervalSince1970: 1)
    )

    // MARK: - The stay's own EXIT

    /// Recorded and routed in order, `CLMonitor`'s observed EXIT closes the visit on disk and then,
    /// read back from the file, times it: below the dwell threshold on a dwell circle, on an
    /// EXIT-only fence with the threshold off, and for zero whole seconds.
    @Test(arguments: [(0, 300.0), (1, 300.0), (1, 0.4)])
    @available(iOS 17.0, *)
    func ownExitRecordedAndRoutedTimesTheStay(fenceIndex: Int, seconds: TimeInterval) async throws {
        let fence = fenceIndex == 0 ? Self.circle : Self.exitOnly
        let device = DurableExitDevice()
        let process = await Self.process(on: device)
        process.route()
        let stay = try await Self.observedStay(process, device: device, fence: fence)
        device.advance(seconds)
        let exitedAt = device.clock.wall

        await process.deliver(.unsatisfied, to: fence.id, at: exitedAt)

        let row = try #require(await Self.exitRows(process).last)
        #expect(row.visitId == stay.visitId)
        #expect(row.enteredAt.map { Int($0.timeIntervalSince1970) } == Int(stay.enteredAt.timeIntervalSince1970))
        #expect(row.visitDurationSeconds == Int(exitedAt.timeIntervalSince1970) - Int(stay.enteredAt.timeIntervalSince1970))
        #expect(await process.dwellRows().isEmpty)
        process.end()
    }

    /// Ordinary fractional OS dates, closed through the real storage write and read back from the
    /// file: one the old seconds-since-1970 round trip changes, the next representable value after
    /// a whole second, and one that round-trips anyway. The stored closure holds the exact bits,
    /// and the EXIT routed with the callback's own Date times its pair.
    @Test(arguments: [810907800.1, 810907800.0.nextUp, 810907800.1234567])
    @available(iOS 17.0, *)
    func fractionalOwnExitDateClosesAndTimesTheStay(referenceSeconds: TimeInterval) async throws {
        let exitedAt = Date(timeIntervalSinceReferenceDate: referenceSeconds)
        let device = DurableExitDevice()
        device.clock.wall = exitedAt.addingTimeInterval(-700)
        device.dateUtil.givenNow = device.clock.wall
        let process = await Self.process(on: device)
        process.route()
        let stay = try await Self.observedStay(process, device: device, fence: Self.exitOnly)
        process.dieOnNextEvent()
        device.advance(exitedAt.timeIntervalSince(device.clock.wall))

        await process.deliver(.unsatisfied, to: Self.exitOnly.id, at: exitedAt)
        let closed = try #require(await process.storage.getDwellVisit(geofenceId: Self.exitOnly.id))
        #expect(
            closed.closedByObservedBoundary?.timeIntervalSinceReferenceDate.bitPattern
                == exitedAt.timeIntervalSinceReferenceDate.bitPattern
        )
        // What the binder's routing task would have done with this EXIT.
        await process.resolver.handleTransition(
            identifier: Self.exitOnly.id, transition: .exit, occurredAt: exitedAt, receivedForUserId: "user-a"
        )

        let row = try #require(await Self.exitRows(process).last)
        #expect(row.visitId == stay.visitId)
        #expect(row.visitDurationSeconds == Int(exitedAt.timeIntervalSince1970) - Int(stay.enteredAt.timeIntervalSince1970))
        process.end()
    }

    // MARK: - A later, different EXIT

    /// The stay's EXIT, and the return's crossing ENTER, are recorded but neither routed: the process
    /// dies. The next process, over the same files, routes a later EXIT. The old visit is still
    /// stored, closed by the first EXIT; the later EXIT is not its end and must not report its
    /// entry or duration.
    @Test
    @available(iOS 17.0, *)
    func laterExitAfterAClosedStayReportsNoOldDuration() async throws {
        let device = DurableExitDevice()
        let first = await Self.process(on: device)
        first.route()
        let stay = try await Self.observedStay(first, device: device, fence: Self.exitOnly)
        first.dieOnNextEvent()
        device.advance(300)
        let exitedAt = device.clock.wall
        await first.deliver(.unsatisfied, to: Self.exitOnly.id)
        device.advance(30)
        await first.deliver(.satisfied, to: Self.exitOnly.id)
        #expect(await first.storage.getDwellVisit(geofenceId: Self.exitOnly.id)?.closedByObservedBoundary == exitedAt)
        first.end()
        device.advance(60)

        let second = await Self.process(on: device)
        second.route()
        await second.register(Self.exitOnly, seenAt: device.fix(at: Self.exitOnly))
        device.advance(30)
        await second.deliver(.unsatisfied, to: Self.exitOnly.id)

        let row = try #require(await Self.exitRows(second).last)
        #expect(row.visitId == nil)
        #expect(row.visitId != stay.visitId)
        #expect(row.enteredAt == nil)
        #expect(row.visitDurationSeconds == nil)
        second.end()
    }

    /// A representably distinct EXIT in the same millisecond as the one that closed the visit is
    /// not that EXIT: untimed. The closing EXIT itself, in the same second as the entry, still
    /// reports zero. Internal chronology: the second EXIT is routed through the resolver, as the
    /// binder's task would, without a monitor event of its own; not physical acceptance.
    @Test(arguments: [false, true])
    @available(iOS 17.0, *)
    func exitInTheSameMillisecondButNotTheSameDateIsUntimed(ownDate: Bool) async throws {
        let device = DurableExitDevice()
        let process = await Self.process(on: device)
        process.route()
        let stay = try await Self.observedStay(process, device: device, fence: Self.exitOnly)
        process.dieOnNextEvent()
        device.advance(0.25)
        let closedAt = device.clock.wall
        await process.deliver(.unsatisfied, to: Self.exitOnly.id, at: closedAt)
        let routedAt = ownDate ? closedAt : closedAt.addingTimeInterval(0.000_003)
        #expect(Int64((routedAt.timeIntervalSince1970 * 1000).rounded(.down)) == Int64((closedAt.timeIntervalSince1970 * 1000).rounded(.down)))

        await process.resolver.handleTransition(
            identifier: Self.exitOnly.id, transition: .exit, occurredAt: routedAt, receivedForUserId: "user-a"
        )

        let row = try #require(await Self.exitRows(process).last)
        #expect(row.visitId == (ownDate ? stay.visitId : nil))
        #expect(row.visitDurationSeconds == (ownDate ? 0 : nil))
        process.end()
    }

    // MARK: - Qualified stays and ambiguous boots

    /// A stay whose dwell is emitted, or reserved and never queued, is closed on disk by its own
    /// EXIT while the process dies before routing it. Its id, flags and reservation are as they
    /// were; that exact EXIT, routed afterwards as the binder's task would, still times it.
    /// Internal chronology for the routing; the closure is the real monitor write.
    @Test(arguments: [true, false])
    @available(iOS 17.0, *)
    func qualifiedStayClosedByItsOwnExitKeepsItsFactsAndIsTimedByIt(emitted: Bool) async throws {
        let device = DurableExitDevice()
        let process = await Self.process(on: device)
        process.route()
        let stay = try await Self.observedStay(process, device: device, fence: Self.circle)
        let qualified = try await Self.qualify(stay, process: process, device: device, emitted: emitted)
        process.dieOnNextEvent()
        device.advance(60)
        let exitedAt = device.clock.wall

        await process.deliver(.unsatisfied, to: Self.circle.id, at: exitedAt)
        let closed = try #require(await process.visit())
        await process.resolver.handleTransition(
            identifier: Self.circle.id, transition: .exit, occurredAt: exitedAt, receivedForUserId: "user-a"
        )

        #expect(closed.closedByObservedBoundary == exitedAt)
        #expect(closed.visitId == qualified.visitId)
        #expect(closed.emitted == qualified.emitted)
        #expect(closed.dwellReservation == qualified.dwellReservation)
        let row = try #require(await Self.exitRows(process).last)
        #expect(row.visitId == stay.visitId)
        #expect(row.visitDurationSeconds == 660)
        #expect(await process.dwellRows().count == (emitted ? 1 : 0))
        process.end()
    }

    /// The same emitted stay closed by its own EXIT, then a process on a boot it cannot prove is the
    /// same (the wall clock, and with it the boot time, set forward). The marker is kept, but its
    /// own EXIT is untimed: nothing is measured across the boot.
    @Test
    @available(iOS 17.0, *)
    func ownExitReadAfterAnAmbiguousBootIsUntimed() async throws {
        let device = DurableExitDevice()
        let first = await Self.process(on: device)
        first.route()
        let stay = try await Self.observedStay(first, device: device, fence: Self.circle)
        _ = try await Self.qualify(stay, process: first, device: device, emitted: true)
        first.dieOnNextEvent()
        device.advance(60)
        let exitedAt = device.clock.wall
        await first.deliver(.unsatisfied, to: Self.circle.id, at: exitedAt)
        first.end()
        device.stepWall(3600)
        device.clock.boot = GeofenceBootIdentity(bootTime: (device.clock.boot.bootTime ?? 0) + 3600, processToken: nil)

        let second = await Self.process(on: device)
        #expect(await second.visit()?.visitId == stay.visitId)
        await second.resolver.handleTransition(
            identifier: Self.circle.id, transition: .exit, occurredAt: exitedAt, receivedForUserId: "user-a"
        )

        let row = try #require(await Self.exitRows(second).last)
        #expect(row.visitId == nil)
        #expect(row.visitDurationSeconds == nil)
        #expect(await second.dwellRows().count == 1)
        second.end()
    }

    // MARK: - Helpers

    @available(iOS 17.0, *)
    private static func process(on device: DurableExitDevice) async -> DurableExitProcess {
        let process = await DurableExitProcess(device: device)
        let fences = [DurableExitFences.circle, DurableExitFences.polygon, exitOnly]
        await process.storage.setCachedGeofences(fences)
        await process.storage.recordRegistration(
            center: LocationData(latitude: 1, longitude: 2), businessIds: Set(fences.map(\.id))
        )
        return process
    }

    /// Registered from a fix outside it, so the next satisfied event is an observed crossing.
    @available(iOS 17.0, *)
    private static func observedStay(
        _ process: DurableExitProcess, device: DurableExitDevice, fence: Geofence
    ) async throws -> GeofenceDwellVisit {
        await process.register(fence, seenAt: device.fix(at: fence, latitudeOffset: 0.01))
        await process.deliver(.satisfied, to: fence.id)
        let stay = try #require(await process.storage.getDwellVisit(geofenceId: fence.id))
        try #require(stay.entryObserved)
        process.dwell.cancelEvidence(for: fence.id)
        return stay
    }

    /// Qualifies `stay` 600 s after its entry: emitted through fresh inside evidence, or reserved
    /// and never queued, as an outbox write that failed leaves it.
    @available(iOS 17.0, *)
    private static func qualify(
        _ stay: GeofenceDwellVisit, process: DurableExitProcess, device: DurableExitDevice, emitted: Bool
    ) async throws -> GeofenceDwellVisit {
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
        return try #require(await process.visit())
    }

    @available(iOS 17.0, *)
    private static func exitRows(_ process: DurableExitProcess) async -> [PendingGeofenceMetric] {
        await process.outbox.rows().filter { $0.transition == .exit }.sorted { $0.timestamp < $1.timestamp }
    }
}
