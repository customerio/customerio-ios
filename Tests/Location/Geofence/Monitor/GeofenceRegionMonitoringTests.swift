@testable import CioInternalCommon
@testable import CioLocation
import Foundation
import SharedTests
import Testing

@Suite("GeofenceRegionMonitoring")
struct GeofenceRegionMonitoringTests {
    @Test
    func startMonitoring_givenRegion_expectTracked() {
        let monitor = MockGeofenceRegionMonitor()
        let center = LocationData(latitude: 37.7749, longitude: -122.4194)
        monitor.startMonitoring(identifier: "test_region", center: center, radius: 200, transitionTypes: [.enter, .exit])
        #expect(monitor.monitoredRegionIdentifiers.contains("test_region"))
        #expect(monitor.startedRegions.count == 1)
        #expect(monitor.startedRegions.first?.identifier == "test_region")
        #expect(monitor.startedRegions.first?.radius == 200)
    }

    @Test
    func startMonitoring_givenTransitionTypes_expectStoredCorrectly() {
        let monitor = MockGeofenceRegionMonitor()
        let center = LocationData(latitude: 37.7749, longitude: -122.4194)
        monitor.startMonitoring(identifier: "enter_only", center: center, radius: 100, transitionTypes: [.enter])
        monitor.startMonitoring(identifier: "exit_only", center: center, radius: 100, transitionTypes: [.exit])
        #expect(monitor.startedRegions[0].transitionTypes == [.enter])
        #expect(monitor.startedRegions[1].transitionTypes == [.exit])
    }

    @Test
    func stopMonitoring_givenTrackedRegion_expectRemoved() {
        let monitor = MockGeofenceRegionMonitor()
        let center = LocationData(latitude: 37.7749, longitude: -122.4194)
        monitor.startMonitoring(identifier: "test_region", center: center, radius: 200, transitionTypes: [.enter, .exit])
        monitor.stopMonitoring(identifier: "test_region")
        #expect(!monitor.monitoredRegionIdentifiers.contains("test_region"))
        #expect(monitor.stoppedIdentifiers == ["test_region"])
    }

    @Test
    func stopMonitoringAll_givenMultipleRegions_expectAllRemoved() {
        let monitor = MockGeofenceRegionMonitor()
        let center = LocationData(latitude: 37.7749, longitude: -122.4194)
        monitor.startMonitoring(identifier: "region_1", center: center, radius: 100, transitionTypes: [.enter, .exit])
        monitor.startMonitoring(identifier: "region_2", center: center, radius: 200, transitionTypes: [.enter, .exit])
        monitor.stopMonitoringAll()
        #expect(monitor.monitoredRegionIdentifiers.isEmpty)
        #expect(monitor.stopAllCallCount == 1)
    }

    @Test
    func onTransition_givenEnterWithLocation_expectCallbackReceivesAll() {
        let monitor = MockGeofenceRegionMonitor()
        var receivedIdentifier: String?
        var receivedTransition: GeofenceTransition?
        var receivedLocation: LocationData?

        monitor.onTransition = { identifier, transition, location in
            receivedIdentifier = identifier
            receivedTransition = transition
            receivedLocation = location
        }

        let location = LocationData(latitude: 37.78, longitude: -122.42)
        monitor.simulateTransition(identifier: "geo_1", transition: .enter, location: location)

        #expect(receivedIdentifier == "geo_1")
        #expect(receivedTransition == .enter)
        #expect(receivedLocation?.latitude == 37.78)
    }

    @Test
    func onTransition_givenNilLocation_expectNilPassedThrough() {
        let monitor = MockGeofenceRegionMonitor()
        var receivedLocation: LocationData? = LocationData(latitude: 0, longitude: 0)

        monitor.onTransition = { _, _, location in
            receivedLocation = location
        }

        monitor.simulateTransition(identifier: "geo_1", transition: .exit, location: nil)
        #expect(receivedLocation == nil)
    }

    @Test
    func startMonitoring_givenMultipleRegions_expectTrackedIndependently() {
        let monitor = MockGeofenceRegionMonitor()
        let c1 = LocationData(latitude: 1, longitude: 2)
        let c2 = LocationData(latitude: 3, longitude: 4)
        monitor.startMonitoring(identifier: "a", center: c1, radius: 100, transitionTypes: [.enter])
        monitor.startMonitoring(identifier: "b", center: c2, radius: 200, transitionTypes: [.exit])
        #expect(monitor.monitoredRegionIdentifiers == Set(["a", "b"]))
        monitor.stopMonitoring(identifier: "a")
        #expect(monitor.monitoredRegionIdentifiers == Set(["b"]))
    }
}
