@testable import CioInternalCommon
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import Foundation
import SharedTests
import Testing

/// What ends an emitted stay kept across an ambiguous boot: an observed crossing, decisive outside
/// evidence, or a loss this process records. A correction ENTER, a discovery or a still-inside pass
/// does not. Same processes and files as `GeofenceDwellBootAmbiguityTests`.
@Suite("GeofenceDwellBootRelease", .serialized)
@MainActor
struct GeofenceDwellBootReleaseTests {
    private static let polygon = BootAmbiguityDevice.polygon

    /// After the step, an ENTER on the covering circle. A crossing the OS observed ends the old
    /// stay, and the stay it begins qualifies on its own; a correction of an assumed state keeps
    /// it, with no second DWELL. Through the binder and the real resolver.
    @Test(arguments: [true, false])
    func enterAfterAStep_expectOnlyACrossingToEndTheStay(crossing: Bool) async throws {
        let device = BootAmbiguityDevice()
        let (first, emitted) = try await BootAmbiguityProcess.emitted(on: device)
        first.end()
        device.advance(60)
        device.stepWallAndBoot(3600)

        let second = await BootAmbiguityProcess(device: device)
        let monitor = MockGeofenceRegionMonitor()
        second.bind(monitor)
        monitor.simulateTransition(
            identifier: Self.polygon.id, transition: .enter, location: nil, occurredAt: device.clock.wall,
            crossingObserved: crossing
        )
        // The routed ENTER's evaluation has returned once the binder refreshes from its fix.
        let sync = second.sync
        try #require(await settle(timeout: 30) { sync.refreshCallsCount == 1 })
        let current = try #require(await second.visit())
        device.advance(600)
        await second.pass()

        let rows = await second.dwellRows().map(\.visitId)
        if crossing {
            #expect(current.visitId != emitted.visitId)
            #expect(rows == [emitted.visitId, current.visitId])
        } else {
            #expect(current == emitted)
            #expect(rows == [emitted.visitId])
        }
        second.end()
    }

    /// After the step, a fresh fix decisively outside the polygon ends the stay. The device's
    /// return is an observed entry, and that stay qualifies with its own entry.
    @Test
    func freshOutsideFixAfterAStep_expectTheStayEndedAndTheReturnToQualify() async throws {
        let device = BootAmbiguityDevice()
        let (first, emitted) = try await BootAmbiguityProcess.emitted(on: device)
        first.end()
        device.advance(60)
        device.stepWallAndBoot(3600)

        let second = await BootAmbiguityProcess(device: device)
        device.fixOffset = 0.01
        await second.pass()
        #expect(await second.visit() == nil)
        device.advance(10)
        device.fixOffset = 0
        await second.pass()
        let returned = try #require(await second.visit())
        #expect(returned.entryObserved)
        device.advance(600)
        await second.pass()

        let rows = await second.dwellRows()
        try #require(rows.count == 2)
        #expect(rows[0].visitId == emitted.visitId)
        #expect(rows[1].visitId == returned.visitId)
        #expect(rows[1].enteredAt == returned.enteredAt)
        second.end()
    }

    /// A reboot whose uptime already overtook the stay's record, then an observed entry dated a
    /// minute back. Uptimes from two boots order nothing, so the entry is not taken as older than
    /// the stay just because its uptime reads lower: it was processed after the stay was recorded,
    /// so it begins a stay of its own. The resolver's `.entered` call, made directly: the resolver
    /// itself ends the stay on the outside verdict an entry needs first.
    @Test
    func observedEntryOnALaterBootWithLowerUptime_expectANewStay() async throws {
        let device = BootAmbiguityDevice()
        let (first, emitted) = try await BootAmbiguityProcess.emitted(on: device)
        first.end()
        device.clock.wall = device.clock.wall.addingTimeInterval(86400)
        device.clock.uptime = (emitted.timing?.recordedUptime ?? 0) + 30
        device.clock.boot = GeofenceBootIdentity(
            bootTime: device.clock.wall.timeIntervalSince1970 - device.clock.uptime, processToken: nil
        )
        device.dateUtil.givenNow = device.clock.wall

        let second = await BootAmbiguityProcess(device: device)
        await second.dwell.recordInsideEvidence(
            geofence: Self.polygon, at: device.clock.wall.addingTimeInterval(-60), source: "location_evidence",
            beginsNewVisit: true
        )

        let entered = try #require(await second.visit())
        #expect(entered.visitId != emitted.visitId)
        #expect(!entered.emitted)
        second.end()
    }

    /// A reboot to an uptime below the stay's entry, a monitoring loss recorded then, and a read
    /// once uptime has passed the old record. The loss came after the stay, which an earlier
    /// process recorded, though its uptime reads lower: the stay is ended from the moment the loss
    /// is recorded, before the removal task runs.
    @Test
    func lossRecordedOnALaterBoot_expectTheStayEndedWhateverTheUptimes() async throws {
        let device = BootAmbiguityDevice()
        let (first, emitted) = try await BootAmbiguityProcess.emitted(on: device)
        first.end()
        device.clock.wall = device.clock.wall.addingTimeInterval(86400)
        device.clock.uptime = 5000
        device.clock.boot = GeofenceBootIdentity(
            bootTime: device.clock.wall.timeIntervalSince1970 - device.clock.uptime, processToken: nil
        )
        device.dateUtil.givenNow = device.clock.wall

        let second = await BootAmbiguityProcess(device: device)
        let removal = second.dwell.interruptContinuity(geofenceId: Self.polygon.id)
        device.advance(6000)
        #expect(second.dwell.continuityHolds(for: emitted, geofenceId: Self.polygon.id) == false)
        await removal.value

        #expect(await second.visit() == nil)
        second.end()
    }
}
