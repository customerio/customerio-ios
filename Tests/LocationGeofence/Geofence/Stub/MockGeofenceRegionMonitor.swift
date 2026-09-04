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
    /// What each owned region is currently registered with — the mock's stand-in for the classic
    /// monitor's live `CLCircularRegion` and CLMonitor's geometry mirror.
    private var registeredGeometry: [String: MonitoredRegionRecord] = [:]

    /// Seedable OS-persisted set — tests set this to model regions the OS still monitors on a
    /// fresh process (where `activeIdentifiers`, the in-memory ownership filter, starts empty).
    var osMonitoredRegions: Set<String> = []

    /// Identifiers `startMonitoring` should silently drop — models the real monitor's early return
    /// on blocked permission / invalid coordinates, where the region never enters the owned set.
    var rejectedIdentifiers: Set<String> = []
    private(set) var adoptExistingRegionsCallsCount = 0
    private(set) var adoptedIdentifiers: Set<String> = []
    private(set) var adoptedRecords: [String: MonitorRegionRecord] = [:]
    private(set) var reportPermissionTierCallsCount = 0

    var monitoredRegionIdentifiers: Set<String> {
        activeIdentifiers
    }

    /// Defaults to no clamp so existing tests register the configured radius unchanged; tests that
    /// exercise the OS cap set it explicitly.
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
        // Mirror the CLMonitor path: adoption seeds the geometry bookkeeping from the persisted
        // records (stored post-clamp, used as-is), which the re-arm then imposes at the OS — so a
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

    /// Models a condition the OS already holds that this process has NOT adopted — the state a
    /// fresh launch is in before the bootstrap runs, and the one where an ignored add would leave
    /// the OS on a stale circle.
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

    func startMonitoring(identifier: String, center: LocationData, radius: Double, transitionTypes: Set<GeofenceTransition>) {
        // Mirror the real monitors: a rejected id is neither recorded nor owned, and any circle the
        // OS was already holding for it is cleared rather than left live.
        guard !rejectedIdentifiers.contains(identifier) else {
            if osMonitoredRegions.remove(identifier) != nil {
                registeredGeometry.removeValue(forKey: identifier)
                stoppedIdentifiers.append(identifier)
                operationLog.append(.stop(identifier: identifier))
            }
            return
        }
        // `startedRegions` keeps what the caller asked for; `registeredGeometry` keeps what the OS
        // would hold, which is what the unchanged check compares against.
        startedRegions.append(MonitoredRegionRecord(
            identifier: identifier,
            center: center,
            radius: radius,
            transitionTypes: transitionTypes
        ))
        // Models the real CLMonitor path: an add over an identifier the OS already holds is silently
        // ignored and the original circle survives (verified on-device), so the monitor clears the
        // identifier at the OS first. Modelled as the same remove-then-add pair. The classic monitor
        // replaces by identifier, so a caller correct against this mock is correct against both.
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
        // Mirror the real monitors: a successful add is reflected in the OS-persisted set too
        // (classic's `monitoredRegions`, CLMonitor's condition mirror).
        osMonitoredRegions.insert(identifier)
        operationLog.append(.start(identifier: identifier))
    }

    func stopMonitoring(identifier: String) {
        // Mirror both real monitors: stopping a region this process doesn't own is a no-op that
        // never reaches the OS.
        guard activeIdentifiers.remove(identifier) != nil else { return }
        stoppedIdentifiers.append(identifier)
        registeredGeometry.removeValue(forKey: identifier)
        osMonitoredRegions.remove(identifier)
        operationLog.append(.stop(identifier: identifier))
    }

    func stopMonitoringAll() {
        stopAllCallCount += 1
        // Mirror the real monitor: only owned regions are handed to the OS for removal, so anything
        // the OS still holds that this process never adopted survives the call.
        osMonitoredRegions.subtract(activeIdentifiers)
        activeIdentifiers.removeAll()
        registeredGeometry.removeAll()
        operationLog.append(.stopAll)
    }

    /// Mirrors both real monitors: stop what left the set, skip what is registered with the same
    /// circle, start the rest.
    @discardableResult
    func setMonitoredRegions(_ regions: [GeofenceRegionRequest]) -> GeofenceRegionDiff {
        let desiredIdentifiers = Set(regions.map(\.identifier))
        var removed: Set<String> = []
        for identifier in activeIdentifiers.subtracting(desiredIdentifiers) {
            stopMonitoring(identifier: identifier)
            removed.insert(identifier)
        }
        // Mirror the CLMonitor path's sweep against live OS state, so a lossy mirror can't strand a
        // condition on an OS slot. The classic monitor can't sweep — `CLLocationManager` shares
        // `monitoredRegions` app-wide, so it would tear down the host app's regions.
        for identifier in osMonitoredRegions.subtracting(desiredIdentifiers) {
            osMonitoredRegions.remove(identifier)
            registeredGeometry.removeValue(forKey: identifier)
            stoppedIdentifiers.append(identifier)
            operationLog.append(.stop(identifier: identifier))
        }
        var added: Set<String> = []
        for region in regions where !isRegisteredUnchanged(region) {
            // Mirror the real monitors: the previous claim is released before the re-registration,
            // so one the monitor rejects stops counting as registered. Ownership only — what the OS
            // holds (`osMonitoredRegions` / `registeredGeometry`) changes when the OS is told to.
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
        // Owned AND still held by the OS. The OS-side check models the classic monitor's live
        // `monitoredRegions` read; the CLMonitor path instead trusts its staged record, whose add
        // is queued FIFO — in this synchronous mock staged and drained coincide, so one check
        // matches both.
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
        locationIsFresh: Bool = true
    ) {
        onTransition?(identifier, transition, location, occurredAt, locationIsFresh)
    }
}
