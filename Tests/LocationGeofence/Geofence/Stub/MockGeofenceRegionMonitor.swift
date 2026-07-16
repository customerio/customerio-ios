@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation

struct MonitoredRegionRecord: Sendable {
    let identifier: String
    let center: LocationData
    let radius: Double
    let transitionTypes: Set<GeofenceTransition>
}

/// One entry per call into the mock — `operationLog` records these in arrival order
/// so tests can assert sequencing (e.g. that `stopAll` ran before `start`).
enum MockMonitorOperation: Sendable, Equatable {
    case start(identifier: String)
    case stop(identifier: String)
    case stopAll
}

@MainActor
final class MockGeofenceRegionMonitor: GeofenceRegionMonitoring {
    private var onTransition: GeofenceTransitionHandler?
    private(set) var onAuthorizationChanged: GeofenceAuthorizationChangedHandler?
    private(set) var onReconciled: GeofenceReconciledHandler?
    private(set) var setOnTransitionCallsCount = 0
    private(set) var setOnAuthorizationChangedCallsCount = 0
    private(set) var setOnReconciledCallsCount = 0
    private(set) var startedRegions: [MonitoredRegionRecord] = []
    private(set) var stoppedIdentifiers: [String] = []
    private(set) var stopAllCallCount = 0
    private(set) var operationLog: [MockMonitorOperation] = []
    private var activeIdentifiers: Set<String> = []

    /// Seedable OS-persisted set — tests set this to model regions the OS still monitors on a
    /// fresh process (where `activeIdentifiers`, the in-memory ownership filter, starts empty).
    var osMonitoredRegions: Set<String> = []

    /// Identifiers `startMonitoring` should silently drop — models the real monitor's early return
    /// on blocked permission / invalid coordinates, where the region never enters the owned set.
    var rejectedIdentifiers: Set<String> = []
    private(set) var adoptExistingRegionsCallsCount = 0
    private(set) var adoptedIdentifiers: Set<String> = []
    private(set) var reportPermissionTierCallsCount = 0

    var monitoredRegionIdentifiers: Set<String> {
        activeIdentifiers
    }

    var osMonitoredRegionIdentifiers: Set<String> {
        osMonitoredRegions
    }

    func adoptExistingRegions(matching identifiers: Set<String>) {
        adoptExistingRegionsCallsCount += 1
        let adopted = identifiers.intersection(osMonitoredRegions)
        adoptedIdentifiers.formUnion(adopted)
        activeIdentifiers.formUnion(adopted)
    }

    func reportPermissionTier() {
        reportPermissionTierCallsCount += 1
    }

    func setOnTransition(_ handler: GeofenceTransitionHandler?) {
        onTransition = handler
        setOnTransitionCallsCount += 1
    }

    func setOnAuthorizationChanged(_ handler: GeofenceAuthorizationChangedHandler?) {
        onAuthorizationChanged = handler
        setOnAuthorizationChangedCallsCount += 1
    }

    func setOnReconciled(_ handler: GeofenceReconciledHandler?) {
        onReconciled = handler
        setOnReconciledCallsCount += 1
    }

    func startMonitoring(identifier: String, center: LocationData, radius: Double, transitionTypes: Set<GeofenceTransition>) {
        // Mirror the real monitor's early return: a rejected id is neither recorded nor owned.
        guard !rejectedIdentifiers.contains(identifier) else { return }
        startedRegions.append(MonitoredRegionRecord(
            identifier: identifier,
            center: center,
            radius: radius,
            transitionTypes: transitionTypes
        ))
        activeIdentifiers.insert(identifier)
        operationLog.append(.start(identifier: identifier))
    }

    func stopMonitoring(identifier: String) {
        stoppedIdentifiers.append(identifier)
        activeIdentifiers.remove(identifier)
        operationLog.append(.stop(identifier: identifier))
    }

    func stopMonitoringAll() {
        stopAllCallCount += 1
        activeIdentifiers.removeAll()
        operationLog.append(.stopAll)
    }

    func simulateTransition(identifier: String, transition: GeofenceTransition, location: LocationData?) {
        onTransition?(identifier, transition, location)
    }
}
