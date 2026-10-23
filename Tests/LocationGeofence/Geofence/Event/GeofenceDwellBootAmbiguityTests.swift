@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import SharedTests
import Testing

/// A wall-clock step moves `kern.boottime` by the same amount (XNU), so the next process reads a
/// different boot while uptime runs on. That cannot be told from a reboot whose uptime overtook the
/// old one. Across it, a stay whose dwell already went out keeps its visit as the marker that it
/// did, so the same stay never qualifies twice; nothing is measured across it. Each "process" is a
/// fresh set of real objects over the same files: context store, geofence store, outbox, event
/// tracker, dwell coordinator and polygon resolver. Only the clocks, fixes and transport are
/// scripted.
@Suite("GeofenceDwellBootAmbiguity", .serialized)
@MainActor
struct GeofenceDwellBootAmbiguityTests {
    private static let polygon = BootAmbiguityDevice.polygon

    /// The stay is emitted; the process dies; the clock is set an hour either way. The next process
    /// proves the device still inside, and again 600 s later. One DWELL, under the stay's own id,
    /// and its visit unchanged.
    @Test(arguments: [3600.0, -3600.0])
    func wallStepMovingTheBootTime_expectTheEmittedStayKeepsItsOneDwell(step: TimeInterval) async throws {
        let device = BootAmbiguityDevice()
        let (first, emitted) = try await BootAmbiguityProcess.emitted(on: device)
        first.end()
        device.advance(60)
        device.stepWallAndBoot(step)

        let second = await BootAmbiguityProcess(device: device)
        await second.pass()
        device.advance(600)
        await second.pass()

        #expect(await second.dwellRows().map(\.visitId) == [emitted.visitId])
        #expect(await second.visit() == emitted)
        second.end()
    }

    /// The clock is set while the first process still runs, with the boot it read at launch; only
    /// the next process reads the moved boot time.
    @Test(arguments: [3600.0, -3600.0])
    func wallStepSeenByTheEarlierProcess_expectTheEmittedStayKeepsItsOneDwell(step: TimeInterval) async throws {
        let device = BootAmbiguityDevice()
        let (first, emitted) = try await BootAmbiguityProcess.emitted(on: device)
        device.advance(30)
        device.stepWall(step)
        await first.dwell.revalidateVisits()
        #expect(await first.visit() == emitted)
        first.end()
        device.advance(30)
        device.rereadBootAfterStep(step)

        let second = await BootAmbiguityProcess(device: device)
        await second.pass()
        device.advance(600)
        await second.pass()

        #expect(await second.dwellRows().map(\.visitId) == [emitted.visitId])
        #expect(await second.visit() == emitted)
        second.end()
    }

    /// No boot time could be read, so each process has its own token and no two processes can be
    /// placed on one boot. The emitted stay is kept as its marker rather than repeated.
    @Test
    func unreadableBootTime_expectTheEmittedStayKeepsItsOneDwell() async throws {
        let device = BootAmbiguityDevice()
        device.clock.boot = GeofenceBootIdentity(bootTime: nil, processToken: "first-process")
        let (first, emitted) = try await BootAmbiguityProcess.emitted(on: device)
        first.end()
        device.advance(60)
        device.clock.boot = GeofenceBootIdentity(bootTime: nil, processToken: "second-process")

        let second = await BootAmbiguityProcess(device: device)
        await second.pass()
        device.advance(600)
        await second.pass()

        #expect(await second.dwellRows().map(\.visitId) == [emitted.visitId])
        #expect(await second.visit() == emitted)
        second.end()
    }

    /// The first process reserved the dwell and appended its row, then died before writing
    /// `emitted`. After the step the next process delivers the reservation at once — not a whole
    /// threshold later — with its millisecond timestamp, entry and duration unchanged; the outbox
    /// keeps the one row, and no later evidence adds another.
    @Test(arguments: [3600.0, -3600.0])
    func dwellReservedAndQueuedBeforeACrash_expectRedeliveredAtOnceAsReserved(step: TimeInterval) async throws {
        let device = BootAmbiguityDevice()
        let first = await BootAmbiguityProcess(device: device)
        device.fixOffset = 0.01
        await first.pass()
        device.advance(10)
        device.fixOffset = 0
        await first.pass()
        let visit = try #require(await first.visit())
        try #require(visit.entryObserved)
        device.advance(600)
        // What `emitDwellIfQualified` does up to the outbox row.
        let proposed = GeofenceDwellReservation(
            occurredAtEpochMilliseconds: Int64((device.clock.wall.timeIntervalSince1970 * 1000).rounded()),
            enteredAtEpochMilliseconds: Int64((visit.enteredAt.timeIntervalSince1970 * 1000).rounded()),
            durationSeconds: 600, thresholdSeconds: 600, detectionSource: "location_evidence"
        )
        guard case .reserved(let reservation) = await first.storage.reserveDwellEmission(proposed, for: visit, geofenceId: Self.polygon.id) else {
            Issue.record("the reservation was not stored")
            return
        }
        let context = GeofenceDwellContext(
            visitId: visit.visitId, enteredAt: reservation.enteredAt, thresholdSeconds: reservation.thresholdSeconds,
            durationSeconds: reservation.durationSeconds, detectionSource: reservation.detectionSource
        )
        try #require(await first.tracker.trackDwell(
            geofenceId: Self.polygon.id, occurredAt: reservation.occurredAt, context: context, expectedUserId: "user-a"
        ))
        first.end()
        device.advance(60)
        device.stepWallAndBoot(step)

        let second = await BootAmbiguityProcess(device: device)
        await second.dwell.resumePendingVisits(geofences: [Self.polygon])
        for _ in 0 ..< 100 where await second.visit()?.emitted != true {
            try? await Task.sleep(nanoseconds: 20000000)
        }

        let delivered = try #require(await second.visit())
        #expect(delivered.visitId == visit.visitId)
        #expect(delivered.emitted)
        #expect(delivered.dwellReservation == reservation)
        await second.pass()
        device.advance(600)
        await second.pass()
        let rows = await second.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId == visit.visitId)
        #expect(Int64((rows[0].timestamp.timeIntervalSince1970 * 1000).rounded()) == reservation.occurredAtEpochMilliseconds)
        #expect(rows[0].enteredAt == reservation.enteredAt)
        #expect(rows[0].dwellDurationSeconds == 600)
        second.end()
    }

    /// Control: a stay 300 s in, not yet qualified, when the clock is set. None of its time counts
    /// across the step: the next process starts it over at its first fresh proof, so 300 s later
    /// there is still no DWELL, and 600 s after that proof there is one, with no entry or duration.
    @Test
    func unqualifiedStayAcrossAStep_expectItStartsOverAtItsNextProof() async throws {
        let device = BootAmbiguityDevice()
        let first = await BootAmbiguityProcess(device: device)
        await first.pass()
        let candidate = try #require(await first.visit())
        device.advance(300)
        first.end()
        device.stepWallAndBoot(3600)

        let second = await BootAmbiguityProcess(device: device)
        await second.pass()
        let restarted = try #require(await second.visit())
        #expect(restarted.visitId != candidate.visitId)
        device.advance(300)
        await second.pass()
        #expect(await second.dwellRows().isEmpty)
        device.advance(300)
        await second.pass()

        let rows = await second.dwellRows()
        try #require(rows.count == 1)
        #expect(rows[0].visitId == restarted.visitId)
        #expect(rows[0].enteredAt == nil)
        #expect(rows[0].dwellDurationSeconds == nil)
        second.end()
    }

    /// Control: uptime behind the record is a known reboot. The SDK observed nothing across it, so
    /// the old visit ends and a stay proven after it qualifies on its own.
    @Test
    func knownReboot_expectANewStayToQualifyOnItsOwn() async throws {
        let device = BootAmbiguityDevice()
        let (first, emitted) = try await BootAmbiguityProcess.emitted(on: device)
        first.end()
        device.clock.reboot(secondsLater: 120, uptimeAfterBoot: 30)
        device.dateUtil.givenNow = device.clock.wall

        let second = await BootAmbiguityProcess(device: device)
        await second.pass()
        let fresh = try #require(await second.visit())
        #expect(fresh.visitId != emitted.visitId)
        device.advance(600)
        await second.pass()

        #expect(await second.dwellRows().map(\.visitId) == [emitted.visitId, fresh.visitId])
        second.end()
    }

    /// Control: B then A identified before the process died. The marker is still judged by
    /// identity: the next process refuses it, and the stay proven after it qualifies on its own.
    @Test
    func identityChangedBeforeAStep_expectTheMarkerRefused() async throws {
        let device = BootAmbiguityDevice()
        let (first, emitted) = try await BootAmbiguityProcess.emitted(on: device)
        first.contextStore.setUserId("user-b")
        first.contextStore.setUserId("user-a")
        first.end()
        device.advance(60)
        device.stepWallAndBoot(3600)

        let second = await BootAmbiguityProcess(device: device)
        await second.pass()
        let fresh = try #require(await second.visit())
        #expect(fresh.visitId != emitted.visitId)
        device.advance(600)
        await second.pass()

        #expect(await second.dwellRows().map(\.visitId) == [emitted.visitId, fresh.visitId])
        second.end()
    }
}
