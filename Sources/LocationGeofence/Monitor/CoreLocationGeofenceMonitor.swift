import CioInternalCommon
import CoreLocation
import Foundation

/// CLLocationManager-backed geofence region monitor.
///
/// `@MainActor`-isolated because CLLocationManager must be created and called on the main
/// thread, and its delegate callbacks arrive on main. State and OS calls share one
/// isolation domain, so the ownership-set update and the OS dispatch happen atomically with
/// no reentrancy point between them — no locks, no fire-and-forget Tasks, no FIFO assumption.
///
/// Tracks which regions this monitor owns so it does not interfere with regions
/// registered by the host app or other SDKs (CLLocationManager.monitoredRegions is shared app-wide).
@MainActor
final class CoreLocationGeofenceMonitor: NSObject, GeofenceRegionMonitoring, @preconcurrency CLLocationManagerDelegate {
    /// Tier of capability available given the current `CLAuthorizationStatus`. The SDK never
    /// requests permission — the host app owns that — so the monitor adapts to whatever was
    /// granted: `.authorizedAlways` enables background delivery, `.authorizedWhenInUse` falls
    /// back to foreground-only (regions still register and fire while foregrounded),
    /// everything else skips registration.
    enum PermissionTier: Equatable {
        case backgroundDelivery
        case foregroundOnly
        case blocked
    }

    private let manager: CLLocationManager
    private let logger: Logger
    private var onTransition: GeofenceTransitionHandler?
    private var onAuthorizationChanged: GeofenceAuthorizationChangedHandler?
    private var lastLoggedPermissionTier: PermissionTier?
    private var ownedRegionIdentifiers: Set<String> = []
    private struct PendingRegionEvent {
        let identifier: String
        let transition: GeofenceTransition
        let location: LocationData?
    }

    /// Region events received before the bootstrap bound `onTransition` (see `handleRegionEvent`).
    private var pendingEvents: [PendingRegionEvent] = []
    private var isDrainingPendingEvents = false
    private static let maxPendingEvents = 64

    init(logger: Logger) {
        self.manager = CLLocationManager()
        self.logger = logger
        super.init()
        manager.delegate = self
    }

    var monitoredRegionIdentifiers: Set<String> {
        ownedRegionIdentifiers
    }

    var maximumMonitoringRadius: Double {
        manager.maximumRegionMonitoringDistance
    }

    var osMonitoredRegionIdentifiers: Set<String> {
        Set(manager.monitoredRegions.map(\.identifier))
    }

    func adoptExistingRegions(matching identifiers: Set<String>) {
        let adopted = identifiers.intersection(osMonitoredRegionIdentifiers)
        guard !adopted.isEmpty else { return }
        ownedRegionIdentifiers.formUnion(adopted)
        logger.geofenceRegionsAdopted(count: adopted.count)
    }

    func setOnTransition(_ handler: GeofenceTransitionHandler?) {
        onTransition = handler
        drainPendingEventsIfReady()
    }

    func setOnAuthorizationChanged(_ handler: GeofenceAuthorizationChangedHandler?) {
        onAuthorizationChanged = handler
    }

    func startMonitoring(identifier: String, center: LocationData, radius: Double, transitionTypes: Set<GeofenceTransition>) {
        reportPermissionTier()
        guard Self.permissionTier(for: currentAuthorizationStatus()) != .blocked else { return }

        let coordinate = CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            logger.geofenceInvalidCoordinatesForRegion(identifier)
            return
        }

        let clampedRadius = min(radius, manager.maximumRegionMonitoringDistance)
        let region = CLCircularRegion(center: coordinate, radius: clampedRadius, identifier: identifier)
        region.notifyOnEntry = transitionTypes.contains(.enter)
        region.notifyOnExit = transitionTypes.contains(.exit)

        ownedRegionIdentifiers.insert(identifier)
        manager.startMonitoring(for: region)
    }

    func stopMonitoring(identifier: String) {
        guard ownedRegionIdentifiers.remove(identifier) != nil else { return }
        if let region = manager.monitoredRegions.first(where: { $0.identifier == identifier }) {
            manager.stopMonitoring(for: region)
        }
    }

    func stopMonitoringAll() {
        let identifiers = ownedRegionIdentifiers
        ownedRegionIdentifiers.removeAll()
        for identifier in identifiers {
            if let region = manager.monitoredRegions.first(where: { $0.identifier == identifier }) {
                manager.stopMonitoring(for: region)
            }
        }
    }

    @discardableResult
    func setMonitoredRegions(_ regions: [GeofenceRegionRequest]) -> GeofenceRegionDiff {
        let desiredIdentifiers = Set(regions.map(\.identifier))
        var removed: Set<String> = []
        for identifier in ownedRegionIdentifiers.subtracting(desiredIdentifiers) {
            stopMonitoring(identifier: identifier)
            removed.insert(identifier)
        }
        var added: Set<String> = []
        for region in regions where !isRegisteredUnchanged(region) {
            // Explicit stop before start (no-op when unowned): `startMonitoring(for:)` replaces by
            // identifier, but the pair keeps the OS-side sequence identical on both monitors.
            stopMonitoring(identifier: region.identifier)
            startMonitoring(
                identifier: region.identifier,
                center: region.center,
                radius: region.radius,
                transitionTypes: region.transitionTypes
            )
            // Blocked permission / invalid coordinates make `startMonitoring` a no-op; the caller's
            // initial-enter decision must not count a region the OS never took.
            if ownedRegionIdentifiers.contains(region.identifier) { added.insert(region.identifier) }
        }
        return GeofenceRegionDiff(added: added, removed: removed)
    }

    /// True when this monitor owns the region and the OS holds an identical circle, so re-registering
    /// would only risk absorbing an undelivered crossing. Geometry comes from the live
    /// `CLCircularRegion` rather than our own bookkeeping, so a region the OS reshaped or dropped
    /// re-registers rather than being trusted.
    private func isRegisteredUnchanged(_ region: GeofenceRegionRequest) -> Bool {
        guard ownedRegionIdentifiers.contains(region.identifier),
              let existing = manager.monitoredRegions.first(where: { $0.identifier == region.identifier }) as? CLCircularRegion
        else { return false }
        var registeredTypes: Set<GeofenceTransition> = []
        if existing.notifyOnEntry { registeredTypes.insert(.enter) }
        if existing.notifyOnExit { registeredTypes.insert(.exit) }
        return region.matchesRegistered(
            center: LocationData(latitude: existing.center.latitude, longitude: existing.center.longitude),
            radius: existing.radius,
            transitionTypes: registeredTypes,
            clampedTo: manager.maximumRegionMonitoringDistance
        )
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        handleRegionEvent(region, transition: .enter)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        handleRegionEvent(region, transition: .exit)
    }

    /// Delivers a region event, holding it until the bootstrap binds `onTransition`: on a cold wake
    /// the delegate can go live before bind/adopt run (any DI path constructing the monitor), and a
    /// crossing delivered then would be dropped with no re-emission. Ownership is checked at drain —
    /// after adopt populated it — which still filters buffered host-app events. New arrivals queue
    /// behind any backlog and behind an in-flight drain, so per-region order holds. Capped against a
    /// process that never binds; unlike CLMonitor there is no re-emission, but overflowing the cap
    /// requires bind to never run, and then every buffered event is undeliverable anyway.
    private func handleRegionEvent(_ region: CLRegion, transition: GeofenceTransition) {
        guard region is CLCircularRegion else { return }
        if onTransition == nil || !pendingEvents.isEmpty || isDrainingPendingEvents {
            pendingEvents.append(PendingRegionEvent(identifier: region.identifier, transition: transition, location: currentLocationData()))
            if pendingEvents.count > Self.maxPendingEvents { pendingEvents.removeFirst() }
            drainPendingEventsIfReady()
            return
        }
        guard ownedRegionIdentifiers.contains(region.identifier) else { return }
        onTransition?(region.identifier, transition, currentLocationData())
    }

    private func drainPendingEventsIfReady() {
        guard onTransition != nil, !isDrainingPendingEvents, !pendingEvents.isEmpty else { return }
        isDrainingPendingEvents = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            while self.onTransition != nil, !self.pendingEvents.isEmpty {
                let next = self.pendingEvents.removeFirst()
                guard self.ownedRegionIdentifiers.contains(next.identifier) else { continue }
                self.onTransition?(next.identifier, next.transition, next.location)
            }
            self.isDrainingPendingEvents = false
        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        guard let identifier = region?.identifier,
              ownedRegionIdentifiers.remove(identifier) != nil
        else { return }
        logger.geofenceMonitoringFailed(region: identifier, error: error)
    }

    // iOS 14+ fires this on delegate set with the current status, and again on every change.
    // We surface it to callers so the bootstrap can re-attempt registration when permission
    // improves mid-process (the initial fire after delegate-set is harmless — the bootstrap
    // already read the current status synchronously before installing the handler).
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorizationChanged?()
    }

    // MARK: - Private

    nonisolated static func permissionTier(for status: CLAuthorizationStatus) -> PermissionTier {
        switch status {
        case .authorizedAlways:
            return .backgroundDelivery
        case .authorizedWhenInUse:
            return .foregroundOnly
        case .notDetermined, .restricted, .denied:
            return .blocked
        @unknown default:
            return .blocked
        }
    }

    func reportPermissionTier() {
        let status = currentAuthorizationStatus()
        let tier = Self.permissionTier(for: status)
        guard tier != lastLoggedPermissionTier else { return }
        lastLoggedPermissionTier = tier
        switch tier {
        case .blocked:
            logger.geofencePermissionUnavailable(currentStatus: status)
        case .foregroundOnly:
            logger.geofenceBackgroundDeliveryUnavailable(currentStatus: status)
        case .backgroundDelivery:
            logger.geofenceBackgroundDeliveryAvailable(currentStatus: status)
        }
    }

    private func currentAuthorizationStatus() -> CLAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return manager.authorizationStatus
        } else {
            return CLLocationManager.authorizationStatus()
        }
    }

    private func currentLocationData() -> LocationData? {
        guard let location = manager.location,
              CLLocationCoordinate2DIsValid(location.coordinate)
        else {
            return nil
        }
        return LocationData(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }
}

// MARK: - DI

extension DIGraphShared {
    /// Process-wide singleton. Hand-written rather than via Sourcery's `InjectRegisterShared`
    /// because that template's eager-init resolution test references the property from a
    /// non-isolated context, which clashes with `@MainActor` isolation propagated through
    /// `GeofenceRegionMonitoring`. The override check below mirrors the generated DI accessors
    /// so tests can still substitute via `di.override(value:forType:)`.
    @MainActor
    var geofenceMonitor: GeofenceRegionMonitoring {
        // Explicit type on the optional pins the generic `T` in `getOverriddenInstance()` to
        // the protocol — without it, Swift infers `T` as the concrete `CoreLocationGeofenceMonitor`
        // from the `??` right-hand side and the override lookup misses by key.
        let overridden: GeofenceRegionMonitoring? = getOverriddenInstance()
        if let overridden { return overridden }
        // iOS 18+ uses the CLMonitor-backed monitor: only there does `CLServiceSession` provide a
        // documented way to keep background event delivery alive. iOS 13–17 keep the classic
        // CLLocationManager monitor — the region APIs are deprecated on 17 but still deliver
        // reliably in the background (OS relaunch), whereas iOS 17 CLMonitor has no session and
        // no dependable background story. Revisit lowering this to 17 only if it proves reliable.
        if #available(iOS 18.0, *) {
            return CLMonitorGeofenceMonitor.shared
        }
        return CoreLocationGeofenceMonitor.shared
    }
}

extension CoreLocationGeofenceMonitor {
    @MainActor
    static let shared = CoreLocationGeofenceMonitor(logger: DIGraphShared.shared.logger)
}
