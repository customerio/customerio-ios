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

/// A replacing circle's install writes its monitor record before the OS swaps the circles, and the
/// replaced circle stays live — raising events — until then. Such an event must not advance the
/// replacing circle's record: its baseline is what that circle's own next event is judged against.
/// The real `CLMonitor` wrapper (only CoreLocation faked) with the install parked at the OS,
/// real binder, resolver, coordinator, storage and file outbox. Internal chronology on a scripted
/// clock.
@Suite("GeofenceReplacementBaseline", .serialized, .enabled(if: monitorAvailable))
@MainActor
struct GeofenceReplacementBaselineTests {
    private static let polygon = DurableExitFences.polygon
    private static let oldCenter = LocationData(latitude: 5.002, longitude: 6)
    private static let currentCenter = LocationData(latitude: 5, longitude: 6)

    /// A stay in the polygon's current shape, not yet qualified. The new covering circle's record
    /// is written, seen inside; the old circle, still live, reports an EXIT: the new record is left
    /// as it was. The new circle goes live and reports its own EXIT, which is applied and ends the
    /// stay. 600 s after the stay began the device is back inside: no DWELL for the ended stay, and
    /// the return qualifies on its own.
    @Test
    @available(iOS 17.0, *)
    func replacedCoveringExitAfterTheNewRecord_expectTheRealExitToEndTheStay() async throws {
        let device = DurableExitDevice()
        let process = await DurableExitProcess(device: device)
        process.route()
        device.polygonFixOffset = 0
        await process.register(Self.polygon, center: Self.oldCenter)
        await Self.pass(process)
        let stay = try #require(await process.visit(Self.polygon))
        process.dwell.cancelEvidence(for: Self.polygon.id)

        process.os.holdOperations()
        process.authority.answerCachedLocation = { [device] in device.fix(at: Self.polygon) }
        process.monitor.startMonitoring(
            identifier: Self.polygon.id, center: Self.currentCenter, radius: Self.polygon.radius, transitionTypes: [.enter, .exit]
        )
        for _ in 0 ..< 200 where await process.storage.getMonitorRegionRecords()[Self.polygon.id]?.center != Self.currentCenter {
            try? await Task.sleep(nanoseconds: 10000000)
        }
        process.authority.answerCachedLocation = nil
        let replacing = try #require(await process.storage.getMonitorRegionRecords()[Self.polygon.id])
        #expect(replacing.lastState == .enter)
        device.advance(30)
        await process.deliver(.unsatisfied, to: Self.polygon.id)
        #expect(await process.storage.getMonitorRegionRecords()[Self.polygon.id] == replacing)
        #expect(await process.visit(Self.polygon) == stay)

        process.os.releaseOperations()
        _ = await settleOnMain { process.os.held[Self.polygon.id]?.center == Self.currentCenter }
        await settleQuietly(0.2)
        device.advance(20)
        await process.deliver(.unsatisfied, to: Self.polygon.id)
        #expect(await process.storage.getMonitorRegionRecords()[Self.polygon.id]?.lastState == .exit)
        #expect(await process.visit(Self.polygon) == nil)

        device.advance(560)
        await Self.pass(process)
        #expect(await process.dwellRows().isEmpty)
        let returned = try #require(await process.visit(Self.polygon))
        #expect(returned.visitId != stay.visitId)
        device.advance(600)
        await Self.pass(process)
        #expect(await process.dwellRows().map(\.visitId) == [returned.visitId])
        process.end()
    }

    /// Control: the replacing install is queued, not yet started, so the record is still the old
    /// circle's. Its event advances its own record as before; the install reseeds it later.
    @Test
    @available(iOS 17.0, *)
    func oldCircleEventBeforeTheNewRecord_expectItsOwnRecordAdvanced() async throws {
        let device = DurableExitDevice()
        let process = await DurableExitProcess(device: device)
        await process.register(Self.polygon, center: Self.oldCenter)
        process.os.holdOperations()
        process.monitor.startMonitoring(identifier: "other", center: LocationData(latitude: 7, longitude: 8), radius: 150, transitionTypes: [.enter, .exit])
        process.monitor.startMonitoring(
            identifier: Self.polygon.id, center: Self.currentCenter, radius: Self.polygon.radius, transitionTypes: [.enter, .exit]
        )
        await settleQuietly(0.2)
        device.advance(30)
        let raisedAt = device.clock.wall
        await process.deliver(.satisfied, to: Self.polygon.id)

        let record = await process.storage.getMonitorRegionRecords()[Self.polygon.id]
        #expect(record?.center == Self.oldCenter)
        #expect(record?.lastState == .enter)
        #expect(record?.lastEventDate == raisedAt)
        process.os.releaseOperations()
        process.end()
    }

    /// Control: a cold wake — no generation recorded in this process — is current by contract, and
    /// its event advances the record.
    @Test
    @available(iOS 17.0, *)
    func coldWakeEvent_expectTheRecordAdvanced() async throws {
        let device = DurableExitDevice()
        let first = await DurableExitProcess(device: device)
        await first.register(Self.polygon, center: Self.oldCenter)
        first.end()
        device.advance(30)
        let second = await DurableExitProcess(device: device)
        let raisedAt = device.clock.wall
        await second.deliver(.satisfied, to: Self.polygon.id)

        let record = await second.storage.getMonitorRegionRecords()[Self.polygon.id]
        #expect(record?.lastState == .enter)
        #expect(record?.lastEventDate == raisedAt)
        second.end()
    }

    @available(iOS 17.0, *)
    private static func pass(_ process: DurableExitProcess) async {
        await process.resolver.evaluateMembership(geofenceIds: [polygon.id], reason: .movement, requiresFreshFix: true)
    }
}
