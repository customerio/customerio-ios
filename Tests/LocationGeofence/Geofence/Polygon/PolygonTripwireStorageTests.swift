@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import Testing

@Suite("GeofenceStorage polygon tripwires")
struct PolygonTripwireStorageTests {
    private func makeStorage() -> GeofenceStorage {
        GeofenceStorage(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
    }

    private func tripwire(radius: Double = 100) -> PolygonTripwire {
        PolygonTripwire(center: LocationData(latitude: 1, longitude: 2), radius: radius)
    }

    @Test
    func setPolygonTripwire_expectReadBackAndReplacedInPlace() async {
        let storage = makeStorage()
        await storage.setPolygonTripwire(tripwire(), forIdentifier: "1")
        #expect(await storage.getPolygonTripwires()["1"]?.radius == 100)

        await storage.setPolygonTripwire(tripwire(radius: 250), forIdentifier: "1")
        let tripwires = await storage.getPolygonTripwires()
        #expect(tripwires.count == 1)
        #expect(tripwires["1"]?.radius == 250)
    }

    /// The caller re-registers with the OS only when something actually changed, so a clear that
    /// removed nothing has to report it.
    @Test
    func clearPolygonTripwire_givenNonePlanted_expectFalse() async {
        let storage = makeStorage()
        #expect(await storage.clearPolygonTripwire(forIdentifier: "1") == false)
    }

    @Test
    func clearPolygonTripwire_givenPlanted_expectRemovedAndTrue() async {
        let storage = makeStorage()
        await storage.setPolygonTripwire(tripwire(), forIdentifier: "1")

        #expect(await storage.clearPolygonTripwire(forIdentifier: "1") == true)
        #expect(await storage.getPolygonTripwires().isEmpty)
    }

    /// A polygon that drops out of the registered set is no longer evaluated, so its tripwire names
    /// a condition nothing will plant again. The retained one is the control.
    @Test
    func recordRegistration_givenPolygonEvicted_expectItsTripwirePruned() async {
        let storage = makeStorage()
        await storage.setPolygonTripwire(tripwire(), forIdentifier: "evicted")
        await storage.setPolygonTripwire(tripwire(), forIdentifier: "kept")

        await storage.recordRegistration(center: LocationData(latitude: 1, longitude: 1), businessIds: ["kept"])

        let tripwires = await storage.getPolygonTripwires()
        #expect(tripwires["evicted"] == nil)
        #expect(tripwires["kept"] != nil)
    }

    /// A tripwire's monitor record is keyed by the tripwire identifier, not the geofence id, so the
    /// prune has to name it explicitly or every sync would strip the baseline of a live condition
    /// and the OS's next EXIT would be deduped away.
    @Test
    func recordRegistration_givenLiveTripwire_expectItsMonitorRecordRetained() async {
        let storage = makeStorage()
        let tripwireId = GeofenceInternalIdentifier.tripwire(for: "1")
        await storage.recordMonitorRegistration(
            identifier: tripwireId,
            transitionTypes: [.exit],
            initialState: .enter,
            center: LocationData(latitude: 1, longitude: 2),
            radius: 100
        )

        await storage.recordRegistration(center: LocationData(latitude: 1, longitude: 1), businessIds: ["1"])

        #expect(await storage.getMonitorRegionRecords()[tripwireId] != nil)
    }

    @Test
    func clearUserScopedState_expectTripwiresCleared() async {
        let storage = makeStorage()
        await storage.setPolygonTripwire(tripwire(), forIdentifier: "1")

        await storage.clearUserScopedState()

        #expect(await storage.getPolygonTripwires().isEmpty)
    }
}
