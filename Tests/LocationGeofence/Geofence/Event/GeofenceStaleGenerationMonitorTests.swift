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

/// `CLMonitor` stages a replacing circle synchronously, but its install — the monitor record, then
/// the OS remove and add, then the ledger's confirm — runs later on the serial monitor chain. Until
/// the confirm, the OS keeps raising events from the replaced circle. They are `.expired`: the
/// binder notes no ENTER for them, and their record write closes no visit. Two seams are held
/// open with the fake condition monitor's `holdOperations`:
/// - queued before the record: an earlier install is parked at the OS, so the replacing one has not
///   written its record;
/// - record before confirm: the replacing install has written its record and is parked at the OS.
/// Real `CLMonitor` wrapper (only CoreLocation faked), binder, resolver, storage, file outbox.
/// Internal chronology on a scripted clock.
@Suite("GeofenceStaleGenerationMonitor", .serialized, .enabled(if: monitorAvailable))
@MainActor
struct GeofenceStaleGenerationMonitorTests {
    private static let circle = DurableExitFences.circle
    private static let polygon = DurableExitFences.polygon

    /// The polygon's covering circle moves from (5.002, 6) to (5, 6); the move is staged but queued
    /// behind another install. The resolver proves a stay in the current shape and its DWELL goes
    /// out. The old covering circle then reports a crossing into it: no ENTER is noted, the stay is
    /// kept, and a fresh inside verdict 600 s later queues no second DWELL.
    @Test
    @available(iOS 17.0, *)
    func replacedCoveringCircleCrossingBeforeTheNewRecord_expectTheStayKept() async throws {
        let device = DurableExitDevice()
        let process = await DurableExitProcess(device: device)
        process.route()
        device.polygonFixOffset = 0
        let oldCenter = LocationData(latitude: 5.002, longitude: 6)
        await process.register(Self.polygon, seenAt: device.fix(at: Self.polygon, latitudeOffset: 0.02), center: oldCenter)
        process.os.holdOperations()
        process.monitor.startMonitoring(identifier: "other", center: LocationData(latitude: 7, longitude: 8), radius: 150, transitionTypes: [.enter, .exit])
        process.monitor.startMonitoring(
            identifier: Self.polygon.id, center: LocationData(latitude: 5, longitude: 6), radius: 300, transitionTypes: [.enter, .exit]
        )
        await settleQuietly(0.2)
        #expect(await process.storage.getMonitorRegionRecords()[Self.polygon.id]?.center == oldCenter)

        await Self.pass(process)
        device.advance(600)
        await Self.pass(process)
        let stay = try #require(await process.visit(Self.polygon))
        try #require(stay.emitted)
        device.advance(60)
        await process.deliver(.satisfied, to: Self.polygon.id)

        #expect(await process.visit(Self.polygon) == stay)
        device.advance(600)
        await Self.pass(process)
        #expect(await process.dwellRows().map(\.visitId) == [stay.visitId])
        process.os.releaseOperations()
        process.end()
    }

    /// The circle is re-registered from 120 m to its current 150 m; the new install has written its
    /// record and is parked at the OS. A stay in the current circle went out. The old circle then
    /// reports an EXIT, and the process dies before routing it. It closes nothing, and leaves the
    /// current circle's record as it was: the replaced circle's events do not advance it.
    @Test
    @available(iOS 17.0, *)
    func replacedCircleExitAfterTheNewRecord_expectNoClosure() async throws {
        let device = DurableExitDevice()
        let process = await DurableExitProcess(device: device)
        await process.register(seenAt: device.fix(), radius: 120)
        await process.dwell.handleBoundary(geofence: Self.circle, transition: .enter, occurredAt: device.clock.wall)
        process.dwell.cancelEvidence(for: Self.circle.id)
        device.advance(600)
        await process.dwell.requestQualifyingEvidence(geofenceId: Self.circle.id)
        let stay = try #require(await process.visit())
        try #require(stay.emitted)
        process.dwell.cancelEvidence(for: Self.circle.id)

        process.os.holdOperations()
        process.authority.answerCachedLocation = { [device] in device.fix() }
        process.monitor.startMonitoring(
            identifier: Self.circle.id, center: LocationData(latitude: 1, longitude: 2), radius: 150, transitionTypes: [.enter, .exit]
        )
        for _ in 0 ..< 200 where await process.storage.getMonitorRegionRecords()[Self.circle.id]?.radius != 150 {
            try? await Task.sleep(nanoseconds: 10000000)
        }
        process.authority.answerCachedLocation = nil
        let record = await process.storage.getMonitorRegionRecords()[Self.circle.id]
        #expect(record?.lastState == .enter)
        device.advance(30)
        await process.deliver(.unsatisfied)

        #expect(await process.storage.getMonitorRegionRecords()[Self.circle.id] == record)
        #expect(await process.visit() == stay)
        process.os.releaseOperations()
        process.end()
    }

    @available(iOS 17.0, *)
    private static func pass(_ process: DurableExitProcess) async {
        await process.resolver.evaluateMembership(geofenceIds: [polygon.id], reason: .movement, requiresFreshFix: true)
    }
}
