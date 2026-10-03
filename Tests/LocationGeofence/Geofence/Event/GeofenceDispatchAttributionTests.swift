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

/// `CLMonitor` attributes an event before its record write and hands it on after that await. A
/// newer circle can be staged meanwhile; the event is then stale when it is dispatched, though it
/// was current when attributed. `dispatchedEventCircle` keeps the attribution captured for the
/// write, and only ever moves it to `.expired`. Run on the real `CLMonitor` wrapper's ledger (only
/// CoreLocation faked). The storage await itself is not suspended here: the stage that lands
/// during it is applied between `eventCircle` and `dispatchedEventCircle`, the two producer calls
/// `process(event:)` makes on either side of it, and the result is handed to the real binder the
/// wrapper is bound to. A scripted dispatch seam, not real storage scheduling or device acceptance.
@Suite("GeofenceDispatchAttribution", .serialized, .enabled(if: monitorAvailable))
@MainActor
struct GeofenceDispatchAttributionTests {
    private static let polygon = DurableExitFences.polygon
    private static let oldCenter = LocationData(latitude: 5.002, longitude: 6)
    private static let currentCenter = LocationData(latitude: 5, longitude: 6)

    /// Attributed to the live circle; no newer stage, so it is dispatched as attributed. A newer
    /// circle staged before dispatch makes it `.expired`. A capture already `.expired` stays so,
    /// even once the old circle is staged again and a fresh attribution would call it current.
    @Test
    @available(iOS 17.0, *)
    func dispatchedCircle_expectOnlyEverMovedToExpired() async throws {
        let device = DurableExitDevice()
        let process = await DurableExitProcess(device: device)
        let monitor = process.monitor
        await process.register(Self.polygon, center: Self.oldCenter)
        let raisedAt = device.clock.wall
        let captured = monitor.eventCircle(for: Self.polygon.id, raisedAt: raisedAt)
        guard case .circle(let attributed) = captured else {
            Issue.record("expected the live circle, got \(captured)")
            return
        }
        #expect(attributed.center == Self.oldCenter)
        #expect(monitor.dispatchedEventCircle(captured: captured, for: Self.polygon.id, raisedAt: raisedAt) == captured)

        process.os.holdOperations()
        Self.stage(monitor, center: Self.currentCenter)
        #expect(monitor.dispatchedEventCircle(captured: captured, for: Self.polygon.id, raisedAt: raisedAt) == .expired)
        let expiredCapture = monitor.eventCircle(for: Self.polygon.id, raisedAt: raisedAt)
        #expect(expiredCapture == .expired)

        Self.stage(monitor, center: Self.oldCenter)
        #expect(monitor.eventCircle(for: Self.polygon.id, raisedAt: raisedAt) == captured)
        #expect(monitor.dispatchedEventCircle(captured: expiredCapture, for: Self.polygon.id, raisedAt: raisedAt) == .expired)
        #expect(monitor.dispatchedEventCircle(captured: captured, for: Self.polygon.id, raisedAt: raisedAt) == captured)
        process.os.releaseOperations()
        process.end()
    }

    /// A cold wake: no generation recorded for the id in this process, so the event is current
    /// (`.unknown`), and a registration staged before dispatch does not change that.
    @Test
    @available(iOS 17.0, *)
    func coldWakeCapture_expectStillUnknownAtDispatch() async throws {
        let device = DurableExitDevice()
        let first = await DurableExitProcess(device: device)
        await first.register(Self.polygon, center: Self.oldCenter)
        first.end()
        let second = await DurableExitProcess(device: device)
        let raisedAt = device.clock.wall
        let captured = second.monitor.eventCircle(for: Self.polygon.id, raisedAt: raisedAt)
        #expect(captured == .unknown)

        second.os.holdOperations()
        Self.stage(second.monitor, center: Self.currentCenter)
        #expect(second.monitor.dispatchedEventCircle(captured: captured, for: Self.polygon.id, raisedAt: raisedAt) == .unknown)
        second.os.releaseOperations()
        second.end()
    }

    /// The old covering circle's crossing is attributed while it is live; before it is dispatched
    /// the polygon's new covering circle is staged, a stay in the new shape is proven and its dwell
    /// emitted (or reserved), and the wall clock is set an hour ahead. Dispatched `.expired`, the
    /// binder notes no ENTER; the routed ENTER finds the device still inside the shape. The stay
    /// keeps its id, flags and reservation, and a fresh inside verdict 600 s later queues no
    /// second DWELL.
    @Test(arguments: [false, true])
    @available(iOS 17.0, *)
    func staleDispatchAcrossAWallStep_expectThePolygonStayKept(reserved: Bool) async throws {
        let device = DurableExitDevice()
        let process = await DurableExitProcess(device: device)
        process.route()
        device.polygonFixOffset = 0
        await process.register(Self.polygon, center: Self.oldCenter)
        let raisedAt = device.clock.wall
        let captured = process.monitor.eventCircle(for: Self.polygon.id, raisedAt: raisedAt)
        process.os.holdOperations()
        Self.stage(process.monitor, center: Self.currentCenter)
        let stay = try await Self.qualifiedStay(process, device: device, reserved: reserved)
        device.stepWall(3600)
        device.advance(30)

        let dispatched = process.monitor.dispatchedEventCircle(captured: captured, for: Self.polygon.id, raisedAt: raisedAt)
        #expect(dispatched == .expired)
        process.monitor.onTransition?(Self.polygon.id, .enter, nil, raisedAt, false, dispatched, true)
        await settleQuietly(0.5)

        let kept = try #require(await process.visit(Self.polygon))
        #expect(kept.visitId == stay.visitId)
        #expect(kept.timing == stay.timing)
        #expect(kept.dwellReservation == stay.dwellReservation)
        #expect(reserved || kept == stay)
        device.advance(600)
        await Self.pass(process)
        #expect(await process.dwellRows().map(\.visitId) == [stay.visitId])
        process.os.releaseOperations()
        process.end()
    }

    // MARK: - Helpers

    /// What `startMonitoring` stages synchronously for the polygon's covering circle.
    @available(iOS 17.0, *)
    private static func stage(_ monitor: CLMonitorGeofenceMonitor, center: LocationData) {
        monitor.startMonitoring(identifier: polygon.id, center: center, radius: polygon.radius, transitionTypes: [.enter, .exit])
    }

    @available(iOS 17.0, *)
    private static func pass(_ process: DurableExitProcess) async {
        await process.resolver.evaluateMembership(geofenceIds: [polygon.id], reason: .movement, requiresFreshFix: true)
    }

    /// A stay proven by a resolver pass now, then emitted by a pass 600 s later, or reserved.
    @available(iOS 17.0, *)
    private static func qualifiedStay(
        _ process: DurableExitProcess, device: DurableExitDevice, reserved: Bool
    ) async throws -> GeofenceDwellVisit {
        await pass(process)
        let candidate = try #require(await process.visit(polygon))
        process.dwell.cancelEvidence(for: polygon.id)
        device.advance(600)
        if reserved {
            let reservation = GeofenceDwellReservation(
                occurredAtEpochMilliseconds: Int64((device.clock.wall.timeIntervalSince1970 * 1000).rounded()),
                enteredAtEpochMilliseconds: nil, durationSeconds: nil, thresholdSeconds: 600, detectionSource: "location_evidence"
            )
            guard case .reserved = await process.storage.reserveDwellEmission(reservation, for: candidate, geofenceId: polygon.id) else {
                Issue.record("not reserved")
                return candidate
            }
        } else {
            await pass(process)
        }
        process.dwell.cancelEvidence(for: polygon.id)
        let qualified = try #require(await process.visit(polygon))
        try #require(qualified.emitted != reserved)
        return qualified
    }
}
