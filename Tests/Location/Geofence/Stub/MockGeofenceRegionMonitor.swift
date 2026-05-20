@testable import CioInternalCommon
@testable import CioLocation
import Foundation

struct MonitoredRegionRecord: Sendable {
    let identifier: String
    let center: LocationData
    let radius: Double
    let transitionTypes: Set<GeofenceTransition>
}

@MainActor
final class MockGeofenceRegionMonitor: GeofenceRegionMonitoring {
    private var onTransition: GeofenceTransitionHandler?
    private(set) var startedRegions: [MonitoredRegionRecord] = []
    private(set) var stoppedIdentifiers: [String] = []
    private(set) var stopAllCallCount = 0
    private var activeIdentifiers: Set<String> = []

    var monitoredRegionIdentifiers: Set<String> {
        activeIdentifiers
    }

    func setOnTransition(_ handler: GeofenceTransitionHandler?) {
        onTransition = handler
    }

    func startMonitoring(identifier: String, center: LocationData, radius: Double, transitionTypes: Set<GeofenceTransition>) {
        startedRegions.append(MonitoredRegionRecord(
            identifier: identifier,
            center: center,
            radius: radius,
            transitionTypes: transitionTypes
        ))
        activeIdentifiers.insert(identifier)
    }

    func stopMonitoring(identifier: String) {
        stoppedIdentifiers.append(identifier)
        activeIdentifiers.remove(identifier)
    }

    func stopMonitoringAll() {
        stopAllCallCount += 1
        activeIdentifiers.removeAll()
    }

    func simulateTransition(identifier: String, transition: GeofenceTransition, location: LocationData?) {
        onTransition?(identifier, transition, location)
    }
}
