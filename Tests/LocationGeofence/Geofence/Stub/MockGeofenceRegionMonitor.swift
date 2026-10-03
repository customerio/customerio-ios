@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation

struct MonitoredRegionRecord: Sendable {
    let identifier: String
    let center: LocationData
    let radius: Double
    let transitionTypes: Set<GeofenceTransition>
}

enum MockMonitorOperation: Sendable, Equatable {
    case start(identifier: String)
    case stop(identifier: String)
    case stopAll
}

@MainActor
final class MockGeofenceRegionMonitor: GeofenceRegionMonitoring {
    private var onTransition: GeofenceTransitionHandler?
    private var onMonitoringInterrupted: GeofenceMonitoringInterruptedHandler?
    private(set) var onAuthorizationChanged: GeofenceAuthorizationChangedHandler?
    private(set) var onReconciled: GeofenceReconciledHandler?
    private(set) var setOnTransitionCallsCount = 0
    private(set) var setOnAuthorizationChangedCallsCount = 0
    private(set) var setOnReconciledCallsCount = 0
    private(set) var setOnMonitoringInterruptedCallsCount = 0
    private(set) var startedRegions: [MonitoredRegionRecord] = []
    private(set) var stoppedIdentifiers: [String] = []
    private(set) var stopAllCallCount = 0
    private(set) var operationLog: [MockMonitorOperation] = []
    private var activeIdentifiers: Set<String> = []
    /// The clamped circle the OS holds per identifier.
    private var registeredGeometry: [String: MonitoredRegionRecord] = [:]

    /// Seed to model a fresh process, where ownership (`activeIdentifiers`) starts empty.
    var osMonitoredRegions: Set<String> = []

    var rejectedIdentifiers: Set<String> = []
    private(set) var adoptExistingRegionsCallsCount = 0
    private(set) var adoptedIdentifiers: Set<String> = []
    private(set) var adoptedRecords: [String: MonitorRegionRecord] = [:]
    private(set) var reportPermissionTierCallsCount = 0

    var monitoredRegionIdentifiers: Set<String> {
        activeIdentifiers
    }

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
        // Mirrors CLMonitor: seeds geometry from persisted records, so a later sync doesn't re-add it.
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

    /// An OS-held condition this process hasn't adopted yet.
    func seedOsHeldRegion(identifier: String, center: LocationData, radius: Double, transitionTypes: Set<GeofenceTransition>) {
        registeredGeometry[identifier] = MonitoredRegionRecord(
            identifier: identifier,
            center: center,
            radius: min(radius, maximumMonitoringRadius),
            transitionTypes: transitionTypes
        )
        osMonitoredRegions.insert(identifier)
    }

    /// The clamped circle the OS holds, not what the caller asked for.
    func osGeometry(for identifier: String) -> MonitoredRegionRecord? {
        registeredGeometry[identifier]
    }

    func reportPermissionTier() {
        reportPermissionTierCallsCount += 1
    }

    var locationAccess = GeofenceLocationAccess(delivery: .background, fullAccuracy: true)

    func setOnTransition(_ handler: GeofenceTransitionHandler?) {
        onTransition = handler
        setOnTransitionCallsCount += 1
        onSetOnTransition?()
    }

    /// Runs when the bootstrap binds its transition handler, the start of its synchronous phase, so
    /// a test can queue main-actor work that must not run before registration.
    var onSetOnTransition: (() -> Void)?

    func setOnAuthorizationChanged(_ handler: GeofenceAuthorizationChangedHandler?) {
        onAuthorizationChanged = handler
        setOnAuthorizationChangedCallsCount += 1
    }

    func setOnReconciled(_ handler: GeofenceReconciledHandler?) {
        onReconciled = handler
        setOnReconciledCallsCount += 1
    }

    func setOnMonitoringInterrupted(_ handler: GeofenceMonitoringInterruptedHandler?) {
        onMonitoringInterrupted = handler
        setOnMonitoringInterruptedCallsCount += 1
    }

    var onStartMonitoring: (() -> Void)?

    func startMonitoring(identifier: String, center: LocationData, radius: Double, transitionTypes: Set<GeofenceTransition>) {
        onStartMonitoring?()
        // Mirrors CLMonitor: a rejected id is unowned and any OS circle for it is cleared.
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
        // CLMonitor ignores an add over a held identifier, so the monitor removes first. Classic
        // replaces in place; remove-then-add is correct for both.
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
        // As in both monitors, an unowned region never reaches the OS.
        guard activeIdentifiers.remove(identifier) != nil else { return }
        stoppedIdentifiers.append(identifier)
        registeredGeometry.removeValue(forKey: identifier)
        osMonitoredRegions.remove(identifier)
        operationLog.append(.stop(identifier: identifier))
    }

    var onStopAll: (() -> Void)?

    func stopMonitoringAll() {
        onStopAll?()
        stopAllCallCount += 1
        // Classic semantics: an unadopted OS region survives. CLMonitor clears everything.
        osMonitoredRegions.subtract(activeIdentifiers)
        activeIdentifiers.removeAll()
        registeredGeometry.removeAll()
        operationLog.append(.stopAll)
    }

    @discardableResult
    func setMonitoredRegions(_ regions: [GeofenceRegionRequest]) -> GeofenceRegionDiff {
        let desiredIdentifiers = Set(regions.map(\.identifier))
        var removed: Set<String> = []
        for identifier in activeIdentifiers.subtracting(desiredIdentifiers) {
            stopMonitoring(identifier: identifier)
            removed.insert(identifier)
        }
        // CLMonitor's sweep. Classic can't sweep: `monitoredRegions` includes the host app's regions.
        for identifier in osMonitoredRegions.subtracting(desiredIdentifiers) {
            osMonitoredRegions.remove(identifier)
            registeredGeometry.removeValue(forKey: identifier)
            stoppedIdentifiers.append(identifier)
            operationLog.append(.stop(identifier: identifier))
        }
        var added: Set<String> = []
        for region in regions where !isRegisteredUnchanged(region) {
            // Release ownership first, so a rejected region stops counting as registered.
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
        // Owned AND OS-held: fits both monitors because this mock has no staged-vs-drained gap.
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

    func simulateTransition(
        identifier: String,
        transition: GeofenceTransition,
        location: LocationData?,
        occurredAt: Date = Date(),
        locationIsFresh: Bool = true,
        eventCircle: GeofenceEventCircle? = nil,
        entryObserved: Bool = true
    ) {
        let circle = eventCircle ?? registeredGeometry[identifier].map {
            GeofenceEventCircle.circle(
                MonitoredCircle(center: $0.center, radius: $0.radius, maximumRadius: maximumMonitoringRadius)
            )
        } ?? .unknown
        onTransition?(identifier, transition, location, occurredAt, locationIsFresh, circle, entryObserved)
    }

    func simulateMonitoringInterrupted(identifier: String?) {
        onMonitoringInterrupted?(identifier)
    }
}
