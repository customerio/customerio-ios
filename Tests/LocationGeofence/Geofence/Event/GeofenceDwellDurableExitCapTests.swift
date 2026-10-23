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

/// A circle larger than the device's region-monitoring cap is registered clamped to it, and its
/// monitor record holds the clamped radius. The durable closure must match that record as the
/// registration and the event attribution do: against the fence's radius clamped by the same cap.
/// Same two-process rig as `GeofenceDwellDurableExitTests`: the real `CLMonitor` wrapper with only
/// CoreLocation faked, real files and outbox, and a process that dies by never routing an event.
/// Internal chronology on a scripted clock.
@Suite("GeofenceDwellDurableExitCap", .serialized, .enabled(if: monitorAvailable))
@MainActor
struct GeofenceDwellDurableExitCapTests {
    private static let circle = DurableExitFences.circle

    /// The 150 m circle under a 100 m cap (registered at 100) and under a 10 km cap (registered at
    /// 150). Either way the recorded EXIT closes the stay, and after death a fresh inside fix
    /// queues and reserves nothing for it.
    @Test(arguments: [100.0, 10000.0])
    @available(iOS 17.0, *)
    func exitRecordedUnderTheCapThenDeath_expectTheStayClosed(cap: Double) async throws {
        let device = DurableExitDevice()
        let first = await DurableExitProcess(device: device)
        first.authority.maximumRegionMonitoringDistance = cap
        _ = try await Self.startStay(first)
        #expect(await first.storage.getMonitorRegionRecords()[Self.circle.id]?.radius == min(Self.circle.radius, cap))
        device.advance(600)
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

    /// Controls under the 100 m cap: a registration whose centre is 0.001° off the fence's, or an
    /// older 80 m circle (80 is not min(150, 100)), is not the circle the stay is measured
    /// against. Its EXIT closes nothing.
    @Test(arguments: ["center", "radius"])
    @available(iOS 17.0, *)
    func exitOfAnotherRegistration_expectNoClosure(mismatch: String) async throws {
        let device = DurableExitDevice()
        let process = await DurableExitProcess(device: device)
        process.authority.maximumRegionMonitoringDistance = 100
        process.route()
        if mismatch == "center" {
            await process.register(center: LocationData(latitude: Self.circle.latitude + 0.001, longitude: Self.circle.longitude))
        } else {
            await process.register(radius: 80)
        }
        await process.deliver(.satisfied)
        // That registration's ENTER is not the cached circle's, so it starts no visit. The stay is
        // recorded by the coordinator directly, as another producer's would be.
        #expect(await process.visit() == nil)
        await process.dwell.handleBoundary(geofence: Self.circle, transition: .enter, occurredAt: device.clock.wall)
        let stay = try #require(await process.visit())
        process.dwell.cancelEvidence(for: Self.circle.id)
        process.dieOnNextEvent()
        device.advance(600)
        await process.deliver(.unsatisfied)

        #expect(await process.storage.getMonitorRegionRecords()[Self.circle.id]?.lastState == .exit)
        #expect(await process.visit() == stay)
        process.end()
    }

    /// Control: a polygon's covering circle over the cap (300 m, registered at 100) records an
    /// EXIT; a polygon visit is never closed by it.
    @Test
    @available(iOS 17.0, *)
    func coveringCircleOverTheCap_expectThePolygonVisitNotClosed() async throws {
        let device = DurableExitDevice()
        let process = await DurableExitProcess(device: device)
        process.authority.maximumRegionMonitoringDistance = 100
        let polygon = DurableExitFences.polygon
        await process.register(polygon)
        #expect(await process.storage.getMonitorRegionRecords()[polygon.id]?.radius == 100)
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

    /// Registers the circle, routes `CLMonitor`'s ENTER to start the stay, then dies at the next event.
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
}
