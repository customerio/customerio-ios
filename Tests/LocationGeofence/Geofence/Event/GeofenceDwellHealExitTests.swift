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

/// `CLMonitor`'s baseline heal synthesizes the crossing the OS missed from a settled fix and writes
/// it to the monitor record before handing it on. A healed EXIT is a departure the SDK observed:
/// like an OS EXIT, it must close the visit in that same write, or a process dying before the
/// visit's removal leaves it open across the departure. A healed ENTER is a correction and closes
/// nothing. The real `CLMonitor` wrapper runs the heal (`setMonitoredRegions` over an unchanged
/// registration) with only CoreLocation faked, over real files and outbox; a process "dies" by
/// never routing what it is handed, and the next is new objects over the same files. Internal
/// chronology on a scripted clock.
@Suite("GeofenceDwellHealExit", .serialized, .enabled(if: monitorAvailable))
@MainActor
struct GeofenceDwellHealExitTests {
    private static let circle = DurableExitFences.circle

    /// The stay is started by `CLMonitor`'s routed ENTER; 600 s later a sync's heal sees a fix
    /// settled 1.1 km outside and records the EXIT; then death. The next process's fresh inside fix
    /// queues and reserves nothing for the old stay. Under the 100 m cap the circle is registered,
    /// and healed, at 100 m.
    @Test(arguments: [100000.0, 100.0])
    @available(iOS 17.0, *)
    func healedExitThenDeath_expectNoDwellForTheEndedStay(cap: Double) async throws {
        let device = DurableExitDevice()
        let first = await DurableExitProcess(device: device)
        first.authority.maximumRegionMonitoringDistance = cap
        first.route()
        await first.register()
        await first.deliver(.satisfied)
        try #require(await first.visit() != nil)
        first.dwell.cancelEvidence(for: Self.circle.id)
        first.dieOnNextEvent()
        device.advance(600)
        let outside = device.fix(latitudeOffset: 0.01)
        await first.heal(Self.circle, seeing: outside, until: .exit)

        #expect(await first.visit()?.closedByObservedBoundary == outside.timestamp)
        first.end()
        device.advance(60)
        let second = await DurableExitProcess(device: device)
        await second.freshInsideEvidence()
        #expect(await second.dwellRows().isEmpty)
        #expect(await second.visit()?.dwellReservation == nil)
        second.end()
    }

    /// Control: the record was seen outside while a stay was recorded; a heal from a fix settled
    /// inside records the ENTER. It is a correction, not a crossing: the stay is not closed.
    @Test
    @available(iOS 17.0, *)
    func healedEnter_expectNoClosure() async throws {
        let device = DurableExitDevice()
        let process = await DurableExitProcess(device: device)
        await process.register(seenAt: device.fix(latitudeOffset: 0.01))
        await process.dwell.handleBoundary(geofence: Self.circle, transition: .enter, occurredAt: device.clock.wall)
        process.dwell.cancelEvidence(for: Self.circle.id)
        let stay = try #require(await process.visit())
        device.advance(600)
        await process.heal(Self.circle, seeing: device.fix(), until: .enter)

        #expect(await process.storage.getMonitorRegionRecords()[Self.circle.id]?.lastState == .enter)
        #expect(await process.visit() == stay)
        process.end()
    }

    /// Control: a healed EXIT of a polygon's covering circle closes no polygon visit.
    @Test
    @available(iOS 17.0, *)
    func healedCoveringCircleExit_expectThePolygonVisitNotClosed() async throws {
        let device = DurableExitDevice()
        let process = await DurableExitProcess(device: device)
        let polygon = DurableExitFences.polygon
        await process.register(polygon, seenAt: device.fix(at: polygon))
        let visit = GeofenceDwellVisit(
            visitId: UUID().uuidString, enteredAt: device.clock.wall, geometryRevision: polygon.dwellRevision,
            userId: "user-a", emitted: false, entryObserved: false, dwellReservation: nil,
            timing: GeofenceVisitTiming(enteredAt: device.clock.wall, recordedAt: device.clock.read())
        )
        try #require(await process.storage.saveDwellVisit(visit, geofenceId: polygon.id))
        device.advance(600)
        await process.heal(polygon, seeing: device.fix(at: polygon, latitudeOffset: 0.01), until: .exit)

        #expect(await process.storage.getMonitorRegionRecords()[polygon.id]?.lastState == .exit)
        #expect(await process.visit(polygon) == visit)
        process.end()
    }

    /// Control: the circle was edited to 200 m in the cache while `CLMonitor` still holds the 150 m
    /// registration. A healed EXIT of that registration closes no stay measured against the edit.
    @Test
    @available(iOS 17.0, *)
    func healedExitOfAnOlderRegistration_expectNoClosure() async throws {
        let device = DurableExitDevice()
        let process = await DurableExitProcess(device: device)
        await process.register(seenAt: device.fix())
        let edited = Geofence(
            id: Self.circle.id, latitude: Self.circle.latitude, longitude: Self.circle.longitude, radius: 200,
            name: Self.circle.name, transitionTypes: Self.circle.transitionTypes, lastUpdated: Date(timeIntervalSince1970: 2),
            dwellThresholdSeconds: 600
        )
        await process.storage.setCachedGeofences([edited, DurableExitFences.polygon])
        await process.dwell.handleBoundary(geofence: edited, transition: .enter, occurredAt: device.clock.wall)
        process.dwell.cancelEvidence(for: Self.circle.id)
        let stay = try #require(await process.visit())
        device.advance(600)
        await process.heal(Self.circle, seeing: device.fix(latitudeOffset: 0.01), until: .exit)

        #expect(await process.storage.getMonitorRegionRecords()[Self.circle.id]?.lastState == .exit)
        #expect(await process.visit() == stay)
        process.end()
    }
}

@available(iOS 17.0, *)
extension DurableExitProcess {
    /// A sync passes `geofence`'s unchanged registration while `fix` is the device's best fix: the
    /// monitor heals its baseline. Returns once the record reads `state`.
    func heal(_ geofence: Geofence, seeing fix: CLLocation, until state: GeofenceTransition) async {
        authority.answerCachedLocation = { fix }
        monitor.setMonitoredRegions([
            GeofenceRegionRequest(
                identifier: geofence.id, center: LocationData(latitude: geofence.latitude, longitude: geofence.longitude),
                radius: geofence.radius, transitionTypes: [.enter, .exit]
            )
        ])
        for _ in 0 ..< 200 where await storage.getMonitorRegionRecords()[geofence.id]?.lastState != state {
            try? await Task.sleep(nanoseconds: 10000000)
        }
        await settleQuietly(0.3)
        authority.answerCachedLocation = nil
    }
}
