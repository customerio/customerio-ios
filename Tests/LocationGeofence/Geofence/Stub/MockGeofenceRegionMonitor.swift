@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation

struct MonitoredRegionRecord: Sendable {
    let identifier: String
    let center: LocationData
    let radius: Double
    let transitionTypes: Set<GeofenceTransition>
}

/// OS-side operations in arrival order, so tests can assert sequencing.
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
    /// The circle the OS holds per identifier: stands in for classic's live `CLCircularRegion` and
    /// CLMonitor's condition ledger.
    private var registeredGeometry: [String: MonitoredRegionRecord] = [:]

    /// Regions the OS still monitors; seed it to model a fresh process, where the ownership set
    /// (`activeIdentifiers`) starts empty.
    var osMonitoredRegions: Set<String> = []

    /// Identifiers `startMonitoring` refuses, modelling blocked permission or invalid coordinates.
    var rejectedIdentifiers: Set<String> = []
    private(set) var adoptExistingRegionsCallsCount = 0
    private(set) var adoptedIdentifiers: Set<String> = []
    private(set) var adoptedRecords: [String: MonitorRegionRecord] = [:]
    private(set) var reportPermissionTierCallsCount = 0

    var monitoredRegionIdentifiers: Set<String> {
        activeIdentifiers
    }

    /// No clamp by default; tests that exercise the OS cap set it.
    var maximumMonitoringRadius: Double = .greatestFiniteMagnitude

    var osMonitoredRegionIdentifiers: Set<String> {
        osMonitoredRegions
    }

    func adoptExistingRegions(matching identifiers: Set<String>, records: [String: MonitorRegionRecord]) {
        adoptExistingRegionsCallsCount += 1
        adoptedRecords = records
        let adopted = identifiers.intersection(osMonitoredRegions)
        adoptedIdentifiers.formUnion(adopted)
        activeIdentifiers.formUnion(adopted)
        // Mirrors CLMonitor: adoption seeds geometry from the persisted (post-clamp) records, so a
        // sync right after adopt reads an unchanged region as unchanged instead of re-adding it.
        for identifier in adopted {
            guard let record = records[identifier],
                  let center = record.center, let radius = record.radius
            else { continue }
            registeredGeometry[identifier] = MonitoredRegionRecord(
                identifier: identifier,
                center: center,
                radius: radius,
                transitionTypes: record.transitionTypes
            )
        }
    }

    /// A condition the OS holds that this process has not adopted, as on a fresh launch before
    /// the bootstrap runs.
    func seedOsHeldRegion(identifier: String, center: LocationData, radius: Double, transitionTypes: Set<GeofenceTransition>) {
        registeredGeometry[identifier] = MonitoredRegionRecord(
            identifier: identifier,
            center: center,
            radius: min(radius, maximumMonitoringRadius),
            transitionTypes: transitionTypes
        )
        osMonitoredRegions.insert(identifier)
    }

    /// The circle the OS is holding, as opposed to what the caller last asked for.
    func osGeometry(for identifier: String) -> MonitoredRegionRecord? {
        registeredGeometry[identifier]
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

    /// Runs inside `startMonitoring`, so a test can land work mid-registration.
    var onStartMonitoring: (() -> Void)?

    func startMonitoring(identifier: String, center: LocationData, radius: Double, transitionTypes: Set<GeofenceTransition>) {
        onStartMonitoring?()
        // Mirrors CLMonitor: a rejected id is not owned, and any circle the OS held for it is
        // cleared rather than left live on a slot nothing owns.
        guard !rejectedIdentifiers.contains(identifier) else {
            if osMonitoredRegions.remove(identifier) != nil {
                registeredGeometry.removeValue(forKey: identifier)
                stoppedIdentifiers.append(identifier)
                operationLog.append(.stop(identifier: identifier))
            }
            return
        }
        // `startedRegions` keeps the request; `registeredGeometry` keeps the clamped OS circle.
        startedRegions.append(MonitoredRegionRecord(
            identifier: identifier,
            center: center,
            radius: radius,
            transitionTypes: transitionTypes
        ))
        // CLMonitor silently ignores an add over a held identifier, so the monitor removes first;
        // modelled as the same remove-then-add pair. Classic replaces by identifier, so a caller
        // correct against this mock is correct against both.
        if osMonitoredRegions.remove(identifier) != nil {
            stoppedIdentifiers.append(identifier)
            operationLog.append(.stop(identifier: identifier))
        }
        registeredGeometry[identifier] = MonitoredRegionRecord(
            identifier: identifier,
            center: center,
            radius: min(radius, maximumMonitoringRadius),
            transitionTypes: transitionTypes
        )
        activeIdentifiers.insert(identifier)
        osMonitoredRegions.insert(identifier)
        operationLog.append(.start(identifier: identifier))
    }

    func stopMonitoring(identifier: String) {
        // Stopping a region this process doesn't own never reaches the OS, as in both monitors.
        guard activeIdentifiers.remove(identifier) != nil else { return }
        stoppedIdentifiers.append(identifier)
        registeredGeometry.removeValue(forKey: identifier)
        osMonitoredRegions.remove(identifier)
        operationLog.append(.stop(identifier: identifier))
    }

    /// Fired inside `stopMonitoringAll`, so a test can order it against other teardown steps.
    var onStopAll: (() -> Void)?

    func stopMonitoringAll() {
        onStopAll?()
        stopAllCallCount += 1
        // Mirrors the classic monitor: only owned regions are removed, so an unadopted OS region
        // survives. (CLMonitor instead clears every live condition under its monitor name.)
        osMonitoredRegions.subtract(activeIdentifiers)
        activeIdentifiers.removeAll()
        registeredGeometry.removeAll()
        operationLog.append(.stopAll)
    }

    /// Mirrors both monitors: stop what left the set, skip what is registered with the same circle,
    /// start the rest.
    @discardableResult
    func setMonitoredRegions(_ regions: [GeofenceRegionRequest]) -> GeofenceRegionDiff {
        let desiredIdentifiers = Set(regions.map(\.identifier))
        var removed: Set<String> = []
        for identifier in activeIdentifiers.subtracting(desiredIdentifiers) {
            stopMonitoring(identifier: identifier)
            removed.insert(identifier)
        }
        // Mirrors CLMonitor's sweep of live OS state. Classic can't sweep: `monitoredRegions` is
        // shared app-wide, so it would tear down the host app's regions.
        for identifier in osMonitoredRegions.subtracting(desiredIdentifiers) {
            osMonitoredRegions.remove(identifier)
            registeredGeometry.removeValue(forKey: identifier)
            stoppedIdentifiers.append(identifier)
            operationLog.append(.stop(identifier: identifier))
        }
        var added: Set<String> = []
        for region in regions where !isRegisteredUnchanged(region) {
            // Ownership is released before re-registration so a rejected region stops counting as
            // registered. OS-side state changes only when `startMonitoring` tells the OS.
            activeIdentifiers.remove(region.identifier)
            startMonitoring(
                identifier: region.identifier,
                center: region.center,
                radius: region.radius,
                transitionTypes: region.transitionTypes
            )
            if activeIdentifiers.contains(region.identifier) { added.insert(region.identifier) }
        }
        return GeofenceRegionDiff(added: added, removed: removed)
    }

    private func isRegisteredUnchanged(_ region: GeofenceRegionRequest) -> Bool {
        // Owned AND held by the OS. Classic reads live `monitoredRegions`; CLMonitor trusts its
        // staged record. In this synchronous mock staged and drained coincide, so one check fits both.
        guard activeIdentifiers.contains(region.identifier),
              osMonitoredRegions.contains(region.identifier),
              let existing = registeredGeometry[region.identifier]
        else { return false }
        return region.matchesRegistered(
            center: existing.center,
            radius: existing.radius,
            transitionTypes: existing.transitionTypes,
            clampedTo: maximumMonitoringRadius
        )
    }

    /// `eventCircle` defaults to the circle registered for `identifier`, so the event is
    /// self-consistent unless a test overrides it.
    func simulateTransition(
        identifier: String,
        transition: GeofenceTransition,
        location: LocationData?,
        occurredAt: Date = Date(),
        locationIsFresh: Bool = true,
        eventCircle: GeofenceEventCircle? = nil
    ) {
        let circle = eventCircle ?? registeredGeometry[identifier].map {
            GeofenceEventCircle.circle(
                MonitoredCircle(center: $0.center, radius: $0.radius, maximumRadius: maximumMonitoringRadius)
            )
        } ?? .unknown
        onTransition?(identifier, transition, location, occurredAt, locationIsFresh, circle)
    }
}
